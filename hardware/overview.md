# piBrick Pocket-CM5 — hardware overview

This device is the [amarullz/piBrick](https://github.com/amarullz/piBrick) **Pocket-CM5**: a
smartphone-sized handheld PC built around a **Raspberry Pi Compute Module 5**. This doc summarizes how
its interactable hardware works and which driver owns each piece — findings from directly inspecting
the running device (kernel driver source, device tree, live `/proc/bus/input/devices`) rather than from
the upstream docs alone.

## Specs (from the upstream README)

- Core: Raspberry Pi CM5
- Display: 3.92" AMOLED multitouch, MIPI/DSI, 1080×1240 @ 90Hz, 16M colors, 450 nits
- HID: BBQ20 QWERTY keyboard w/ integrated trackpad, side rotary encoder(s) with push switch, 5 side
  user buttons
- Battery: 5000 mAh LiPo
- Audio: internal speaker + amp, mic (via the BBQ20 keyboard), 3.5mm jack
- Accelerometer, front MIPI/CSI camera, M.2 NVMe, internal eMMC/microSD

## Where the driver code lives

Three separate upstream repos, each owning a different layer:

| Repo | Owns |
|---|---|
| [amarullz/piBrick](https://github.com/amarullz/piBrick) | Hardware design: PCB/schematic links, 3D case files, product docs |
| [lshaf/pibrick-driver](https://github.com/lshaf/pibrick-driver) | Linux kernel drivers: display panel, touchscreen, battery charger, side buttons |
| [amarullz/pibrick_pocketcm5_keyboard](https://github.com/amarullz/pibrick_pocketcm5_keyboard) | QMK/Vial firmware for the BBQ20 keyboard module (keys, trackpad, scroll wheel) |

On the device itself, both are checked out under `~/pi_brick/` (`piBrick/`, `pibrick-driver/`,
`pibrick_pocketcm5_keyboard/`). This repo (`piBrick` admin repo) does **not** vendor or reimplement
their install steps — see "Relationship to this repo" below.

## Display — Visionox VTDR6110 AMOLED over DSI1

- `panel-pibrick-used.c` implements a standard Linux `drm_panel` driver for a **Visionox VTDR6110**
  AMOLED panel (function names are literally `visionox_vtdr6110_*`), wired to the CM5's DSI1 MIPI port.
  The device tree overlay (`dts/vc4-kms-dsi-pibrick.dts`) binds it: `target = <&dsi1>`, compatible
  `pibrick,amoled`.
- Reset/TE GPIOs declared in the dts are dummy/unused — panel power sequencing happens over the DSI
  command bus itself (`.prepare`/`.unprepare` in the drm_panel ops), not discrete GPIO toggling.
- Backlight is a standard Linux `backlight_device` named `pibrick-backlight`
  (`/sys/class/backlight/pibrick-backlight/brightness`, 0–1023).
- A custom (non-standard) sysfs attribute, `pibrick_display_enable`, fully powers the panel on/off via
  `drm_panel_enable`/`drm_panel_disable` — found by `find /sys -name pibrick_display_enable`.

## Touchscreen — Hynitron CST66xx over I2C0

- Device tree fragment@2 instantiates `hynitron@5A`, `compatible = "hyn,66xx"`, at I2C address `0x5A`
  on `i2c0`. Interrupt-driven: `irq-gpio = GPIO4`, `reset-gpio = GPIO17`.
- `display-coords = <0 0 1080 1240>` matches the panel resolution exactly; `pos-swap = <1>` corrects for
  how the digitizer is physically rotated relative to the panel.
- Linked to the panel node (`panel = <&pibrick>`) so touch reporting can sync with DRM power state.
- Driver source: `hyn_driver_release_qm/` (multi-chip Hynitron family driver, `hyn_cst66xx.c` etc.).
- Note: `fts/ft5x06.c` (FocalTech) also exists in the repo but isn't referenced by any dts fragment —
  appears to be a leftover from an earlier panel revision, not what's actually in use.

## Battery charger — TI bq25890 over I2C1

- Device tree fragment@3: `bq25890@6a`, I2C address `0x6a` on `i2c1`, IRQ on GPIO26.
- Config sets charge voltage/current (4.1V, 4A), termination/precharge current, boost mode (5V/3A, for
  USB power-out), thermal regulation threshold.
- Driver: `battery/bq25890_battery.c`.

## Side buttons — userspace polling, not a kernel driver

`button/pibrickbtn.c`, run by `pibrick.service` (`ExecStart=/usr/local/bin/pibrickbtn`):

- Both the power button and the user button share **one GPIO line**, `gpiochip0` pin 23 — polled via
  `gpiomon --edges=falling`.
- To disambiguate which button was pressed, it reads a second GPIO at press time, `gpiochip10` pin 20
  (`gpiosel_btn()`); that line's level selects power-vs-user.
- **Power button** short press → `power-short.sh` → injects `KEY_POWER` via `evemu-event` into a
  `uinput` virtual device the binary creates at startup (brings up the desktop shutdown dialog). A long
  press is *not* handled in software — held long enough, it's a hard power-off at the PMIC level.
- **User button**, disambiguated by timing windows (`wait_release` 700ms, `wait_second_press` 350ms):
  - short press → `actions/brightness.sh` (steps backlight ±64/1023, wraps)
  - long press (never released in time) → `actions/display-on-off.sh` (toggles `pibrick_display_enable`)
  - double press → `actions/keyboard-toggle.sh` (toggles the **squeekboard** on-screen keyboard over
    D-Bus — a software keyboard, unrelated to the physical BBQ20 one)
- At startup it does `rmmod gpio_keys; rmmod hyn_ts; modprobe hyn_ts` — unloading the generic kernel
  `gpio_keys` driver so it doesn't race with the userspace poller for the same GPIO lines.
- Live customizable copies of the action scripts run from `/etc/pibrick/` (installed there by
  `pibrick-driver`'s `install.sh`); the versions under `button/etc/pibrick/` in the driver repo are the
  source templates.

## Keyboard, trackpad, and side scroll wheel — all one USB-HID device, no Pi-side driver

The BBQ20 keyboard module (with its integrated trackpad and side scroll wheel) needs **zero kernel
driver on the Pi** — it's entirely handled by the keyboard module's own firmware
(`pibrick_pocketcm5_keyboard`, QMK/Vial-based) turning physical input into standard USB-HID reports, and
the Pi's generic in-kernel `usbhid` module picks it up. Confirmed live via
`/proc/bus/input/devices`, which shows it enumerating as **4 separate HID interfaces**, all tagged
`Uniq=vial:f64c2b3c` (the Vial firmware's serial):

| Interface | Handler | Purpose |
|---|---|---|
| `piBrick PocketCM5 Keyboard` | `event5` | regular key matrix |
| `piBrick PocketCM5 Keyboard Mouse` | `event6` | trackpad (`REL_X`/`REL_Y`) **and** the side scroll wheel (`REL_HWHEEL`/`REL_WHEEL`/hi-res variants) — same interface, composited by the firmware |
| `piBrick PocketCM5 Keyboard System Control` | `event7` | HID "System Control" usage page (power/sleep/wake keys) |
| `piBrick PocketCM5 Keyboard Consumer Control` | `event8` | HID "Consumer Control" usage page (media keys) |

Because it's standard HID, it works out of the box under X11, labwc, or niri/Wayland — no udev rules or
custom driver needed for normal use. The one udev rule that *does* exist
(`/etc/udev/rules.d/99-vial.rules`, installed by `pibrick-driver`'s `install.sh`) only relaxes
`/dev/hidraw*` permissions for the logged-in user, so Vial's browser-based WebHID configurator can remap
keys without running as root.

## Relationship to this repo

This repo does not vendor or re-run `pibrick-driver`'s `install.sh` (kernel module build, dtbo install,
`/boot/firmware/config.txt` edits, `pibrick.service`/button setup) — that repo is the source of truth
for the hardware layer and is already installed and working on the device. This repo's Ansible
automation (`ansible/`) only manages the desktop/OS layer on top: dotfiles, VNC, and apt packages. See
[`docs/niri-dms-setup.md`](../docs/niri-dms-setup.md) for how the niri + DankMaterialShell desktop stack
on top of this hardware was built.
