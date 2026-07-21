# pibrick-driver — repo reference

[lshaf/pibrick-driver](https://github.com/lshaf/pibrick-driver): the out-of-tree Linux kernel driver
tree for the piBrick Pocket-CM5's display, touchscreen, battery charger, and side buttons. Cloned on the
device at `~/pi_brick/pibrick-driver`. For *what the hardware does* (subsystem-by-subsystem behavior),
see [`overview.md`](overview.md) — this doc is a repo-structure reference: what's
in the tree and why.

## Install flow

`sudo bash install.sh` (see `INSTALL.md`): installs build deps (`build-essential`, matching
`linux-headers`, `device-tree-compiler`, `gpiod`, `evemu-tools`, `wlr-randr`), stages the whole tree to
`/usr/lib/pibrick/`, installs `pibrick.service`, stages the button action scripts to `/etc/pibrick/`
(user-editable, separate from the repo's own copies), and adds the Vial WebHID udev rule
(`99-vial.rules`). It then runs `build.sh` once and starts the service.

`build.sh` runs on every boot (`pibrick.service`'s `ExecStartPre`):
1. Recompiles `button/pibrickbtn.c` → `/usr/local/bin/pibrickbtn` whenever the source is newer than the
   installed binary — cheap, kernel-version-independent, so this always happens.
2. Compares the running kernel version against `/etc/pibrick.lastbuild`. If unchanged, exits early (no
   kernel module rebuild needed).
3. If the kernel changed: builds and installs three module groups in turn — `make amoled` (panel,
   top-level `Makefile`), `make touch` (`hyn_driver_release_qm/`), `make battery` (`battery/`). Failures
   are tracked per-module but don't stop the others; `/etc/pibrick.lastbuild` is only updated (and the
   device only rebooted) if **all three** succeeded — a failed build is retried on the next boot instead
   of silently leaving stale modules in place.

## Panel driver: which `.c` file is actually built — a naming trap

The top-level `Makefile` has `obj-m += panel-pibrick.o`, which under kbuild means the compiled source
**must be named exactly `panel-pibrick.c`**. That's the file actually built into `panel-pibrick.ko` —
*not* `panel-pibrick-used.c`, despite its name suggesting otherwise. Verified by diffing them: the two
differ in exactly the panel timing constants, and `git log` shows `panel-pibrick.c` (not `-used.c`)
carries the two later fix commits:

```
f63a7ff panel: fix 60Hz right-edge glitch via wider horizontal blanking
dc9993d panel: fix right-edge flicker at 60Hz
```

So `panel-pibrick.c` is the current, patched, actually-in-use driver; `panel-pibrick-used.c` is an
older reference snapshot that predates the 60Hz timing fixes. If you're reading this driver's source to
understand current behavior, read `panel-pibrick.c`, not the one whose name implies it.

The repo also carries several **other panel variants**, none referenced by the Makefile (so none are
built by default) — apparently support for other display revisions/sizes used across piBrick hardware
iterations:

| File | Notes |
|---|---|
| `panel-pibrick.5inch.c`, `panel-pibrick.9202.c`, `panel-pibrick.9203.c`, `panel-pibrick-548inch.c`, `panel-pibrick.test5inch.c` | Alternate panel sizes/revisions |
| `2/panel-pibrick.c`, `3/panel-pibrick.c` | Numbered snapshots — earlier iterations (different refresh-rate constant, `60.768`Hz vs. the current file's) kept for reference, not wired into the build |

Corresponding device-tree overlays live in `dts/`: `vc4-kms-dsi-pibrick.dts` (current AMOLED panel, `make
amoled`) and `vc4-kms-dsi-pibrick-xga.dts` (`make xga`) are the two `Makefile` targets; `9203.dts`,
`vc4-9203.dts`, `vc4-5inch.dts`, `vc-548inch.dts` are for the other panel variants above and aren't
wired into any `Makefile` target — build manually with `dtc` if ever needed.

## Local uncommitted changes (as of this doc)

The checkout on the device is **ahead of `origin/main`** with changes not yet upstreamed:

- `button/pibrickbtn.c` (modified): adds `wait_second_press()`/`wait_release_then_second_press()` and
  the double-press branch in `monitor_keydown()` for the **user** button (short/long/double distinct).
  The power button was also experimented on extensively (see below) but ended up **not** using timing
  disambiguation — it calls one action (`power-short.sh`, now lock screen) on any press, unconditionally.
- New, untracked: `button/deploy.sh`, `button/etc/pibrick/actions/keyboard-toggle.sh`,
  `button/etc/pibrick/user-double.sh` — the user-button double-press → squeekboard-toggle wiring.
- New, untracked: `button/etc/pibrick/actions/lock-screen.sh` — what the power button now calls
  (`dms ipc call lock lock`), replacing the original `KEY_POWER`-injection version of `power-short.sh`.
  `actions/power-menu.sh` (`dms ipc call powermenu open`) also exists, written during the investigation
  below and left in place as a working, reusable script even though nothing currently calls it.

Worth knowing if you're comparing this device's behavior against a fresh clone of the upstream repo, or
if these changes are ever worth contributing back upstream.

### Power-button short/long/double: attempted, investigated at length, abandoned

Tried to give the power button the same short=lock / double or long=power-options behavior as a typical
phone. Extended `monitor_keydown()`'s power branch with the same `wait_release`/`wait_second_press`
disambiguation the user button already had. Result, in order of what was tried and ruled out via direct
evidence (not guessing) each time:

1. **Timeout too short?** Started at the user button's existing 350ms double-press window. Real button
   presses (via `dms ipc call` / journal log tracing added directly into the running binary) showed the
   short-press branch firing even for what should've been clean double-clicks. Widened to 500ms, then
   800ms, then 900ms via a redesigned single-session capture (below) — **no improvement at any width**,
   ruling out "just needs more time."
2. **Race condition between two separate `gpiomon` subprocesses?** The original design called
   `wait_release()` and `wait_second_press()` as two *separate* `gpiomon` invocations back to back —
   a fast second press landing in the handover gap between one subprocess exiting and the next
   acquiring the GPIO line would be silently missed regardless of timeout length. Redesigned into
   `wait_release_then_second_press()`, one continuous `gpiomon --edges=both --num-events=2` session
   with no gap at all. **Also no improvement** — ruled this out too.
3. **`gpiosel_btn()` eating into the window before monitoring even starts?** Measured directly
   (temporary timing instrumentation): ~1ms. Negligible, ruled out.
4. **Direct raw GPIO event tracing** (`gpiomon` run standalone against `gpiochip0` line 23, `pibrick.service`
   stopped to free the line) during a real, deliberate long-press (user held for 1-2s) showed a `rising`
   (release) edge fire almost immediately — while the button was still physically held down. That's
   **contact bounce being misread as a genuine release**, not a software timing bug at all.
5. **Tried hardware debounce**: `gpiomon --debounce-period 15ms`. This made things *worse* — legitimate
   presses stopped registering at all (zero events logged for a real, firm 1s+ hold). Reverted.
6. **After reverting debounce**, behavior was still inconsistent run to run: a plain short press got
   classified as a long press (no release detected in the window) on the very next attempt.

Conclusion: this button's electrical contacts produce enough jitter/bounce that a fixed-timeout,
edge-counting classification scheme in userspace isn't reliably tunable — confirmed via live GPIO
tracing, not assumption. Reverted the power button to the simplest possible design: one unconditional
action per press, no timing logic, no `wait_release_then_second_press()` call at all. This is the one
behavior that worked reliably from the very first test. If double/long-press for the power button is
worth revisiting later, the right next step is probably investigating the actual hardware (schematic,
oscilloscope on the line, or a proper hardware debounce circuit) rather than more userspace timeout
tuning — software already hit its limit here.

**Confirmed hardware fact, learned by direct incident**: holding the power button long enough triggers
an independent forced shutdown at the hardware/PMIC level (likely the bq25890 charger IC's own
long-press cutoff) — completely bypassing `pibrickbtn`/Linux. This happened once during testing: the
device powered off mid-session. Exact duration threshold unknown, only that it's real and shorter than
"a few seconds."

**That abrupt power-off also corrupted `/usr/local/bin/pibrickbtn`** — found truncated to 0 bytes after
the reboot (`gcc` was almost certainly mid-write when power cut), causing
`Failed to execute /usr/local/bin/pibrickbtn: Exec format error` and a boot loop
(`pibrick.service: Start request repeated too quickly`). `build.sh`'s mtime-based rebuild check didn't
catch this — the corrupt file still had its executable bit set, matching `build.sh`'s "already built"
condition. **Recovery**: manually recompile and restart:
```sh
sudo gcc /usr/lib/pibrick/button/pibrickbtn.c -o /usr/local/bin/pibrickbtn
sudo chmod +x /usr/local/bin/pibrickbtn
sudo systemctl reset-failed pibrick.service
sudo systemctl restart pibrick.service
```

**Maintenance trap hit while adding the power-button changes**: `pibrick.service`'s `build.sh` compiles
`pibrickbtn` from `/usr/lib/pibrick/button/pibrickbtn.c` — **not** from this git checkout
(`~/pi_brick/pibrick-driver/`) directly. `/usr/lib/pibrick/` is a one-time-copied install target
(`install.sh`'s `cp -rf ./* /usr/lib/pibrick/`), never automatically re-synced from the checkout on
every edit. Editing `pibrickbtn.c` (or any `button/etc/pibrick/*` action script) in the git checkout
alone has **no effect** until it's also copied into `/usr/lib/pibrick/` — confirmed the hard way: the
service restarted "successfully" and logged `No Linux Kernel Update` (build.sh's early-exit path) with
no compile step at all, because the source it was comparing timestamps against was still the old
version. Same applies to `/etc/pibrick/` (the actually-executed action scripts, staged once by
`install.sh` from `button/etc/pibrick/`) — also not auto-synced from the checkout. After editing
anything under `button/` in this checkout, both `/usr/lib/pibrick/button/` and, for action scripts,
`/etc/pibrick/` need the same files copied over by hand before `systemctl restart pibrick.service` will
actually pick up the change.

## Repo layout

| Path | Purpose |
|---|---|
| `Makefile` | Builds `panel-pibrick.ko`; `amoled`/`xga` targets also compile the matching `.dtbo`; `install`/`remove` targets manage `/boot/firmware/config.txt` (`ignore_lcd=1` + `dtoverlay=`) |
| `install.sh`, `INSTALL.md` | Top-level installer (see "Install flow" above) |
| `build.sh` | Per-boot rebuild driver, run by `pibrick.service` |
| `pibrick.service` | systemd unit: `ExecStartPre=build.sh`, `ExecStart=/usr/local/bin/pibrickbtn` |
| `panel-pibrick.c` | **The** active DRM panel driver (Visionox VTDR6110 AMOLED) — see naming trap above |
| `panel-pibrick-used.c`, `panel-pibrick.*.c`, `2/`, `3/` | Other panel variants/snapshots, not built by default |
| `dts/` | Device-tree overlay sources, one per panel variant |
| `hyn_driver_release_qm/` | Hynitron multi-chip touchscreen driver (`make touch`) — `hyn_core.c` + per-chip drivers under `hyn_chips/`, shared logic under `hyn_lib/` |
| `fts/` | FocalTech `ft5x06` touch driver — present but unreferenced by any dts fragment; not the touch chip actually on this device |
| `battery/` | TI bq25890 charger driver (`make battery`) |
| `button/` | `pibrickbtn.c` (userspace GPIO button monitor), `etc/pibrick/` (action script templates staged to `/etc/pibrick` by `install.sh`), `README.md`, `deploy.sh` |
| `addon/disp.c`, `addon/buildisp.sh` | Minimal standalone libdrm test program — opens `/dev/dri/card1`, finds the connected connector/encoder/mode. A bring-up/debug tool, not part of the installed system |
| `gp.py` | `gpiozero` one-off script to monitor GPIO20 (one of the two button-disambiguation GPIOs) — a debug/dev aid, not run in production |
| `gpio/test_gpio.sh` | Cycles a list of GPIOs as outputs in sequence — hardware bring-up/LED test aid |
