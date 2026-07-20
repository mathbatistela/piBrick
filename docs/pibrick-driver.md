# pibrick-driver — repo reference

[lshaf/pibrick-driver](https://github.com/lshaf/pibrick-driver): the out-of-tree Linux kernel driver
tree for the piBrick Pocket-CM5's display, touchscreen, battery charger, and side buttons. Cloned on the
device at `~/pi_brick/pibrick-driver`. For *what the hardware does* (subsystem-by-subsystem behavior),
see [`hardware/overview.md`](../hardware/overview.md) — this doc is a repo-structure reference: what's
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

- `button/pibrickbtn.c` (modified): adds `wait_second_press()` and the double-press branch in
  `monitor_keydown()` for the user button (short/long/double distinct), **and** extends the exact same
  short/long/double disambiguation to the power button, which previously fired one unconditional action
  on any press. See `hardware/overview.md` for current behavior of both buttons.
- New, untracked: `button/deploy.sh`, `button/etc/pibrick/actions/keyboard-toggle.sh`,
  `button/etc/pibrick/user-double.sh` — the user-button double-press → squeekboard-toggle wiring.
- New, untracked: `button/etc/pibrick/power-double.sh`, `button/etc/pibrick/power-long.sh`,
  `button/etc/pibrick/actions/lock-screen.sh`, `button/etc/pibrick/actions/power-menu.sh` — the
  power-button short/long/double wiring (lock screen / power options menu).

Worth knowing if you're comparing this device's behavior against a fresh clone of the upstream repo, or
if these changes are ever worth contributing back upstream.

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
