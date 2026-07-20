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

| Repo | Owns | Repo-structure reference |
|---|---|---|
| [amarullz/piBrick](https://github.com/amarullz/piBrick) | Hardware design: PCB/schematic links, 3D case files, product docs | [`docs/piBrick-hw-repo.md`](../docs/piBrick-hw-repo.md) |
| [lshaf/pibrick-driver](https://github.com/lshaf/pibrick-driver) | Linux kernel drivers: display panel, touchscreen, battery charger, side buttons | [`docs/pibrick-driver.md`](../docs/pibrick-driver.md) |
| [amarullz/pibrick_pocketcm5_keyboard](https://github.com/amarullz/pibrick_pocketcm5_keyboard) | QMK/Vial firmware for the BBQ20 keyboard module (keys, trackpad, scroll wheel) | — (see the "Keyboard module" section below) |

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

## Carrier-board buttons (power + 1 user button) — userspace polling, not a kernel driver

Note: this is a **different physical pair** from the keyboard module's own 5 "User Buttons" + rotary
encoder covered below — these two are wired directly to the CM5 carrier board itself.

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

## Keyboard module — RP2040 running QMK/Vial, all one USB-HID device, no Pi-side driver

The BBQ20 keyboard module (key matrix, trackpad, 5 user buttons, rotary encoder + push switch, RGB
indicators, backlight) is its own standalone computer: a **Raspberry Pi RP2040**, running
[amarullz/pibrick_pocketcm5_keyboard](https://github.com/amarullz/pibrick_pocketcm5_keyboard), a
QMK/[Vial](https://vial.rocks) firmware. It needs **zero kernel driver on the Pi CM5 side** — the RP2040
turns all physical input into standard USB-HID reports, and the Pi's generic in-kernel `usbhid` module
just picks it up. Confirmed live via `/proc/bus/input/devices`, which shows it enumerating as **4
separate HID interfaces**, all tagged `Uniq=vial:f64c2b3c` (the Vial firmware's serial):

| Interface | Handler | Purpose |
|---|---|---|
| `piBrick PocketCM5 Keyboard` | `event5` | regular key matrix |
| `piBrick PocketCM5 Keyboard Mouse` | `event6` | trackpad (`REL_X`/`REL_Y`) **and** the rotary encoder acting as a scroll wheel (`REL_HWHEEL`/`REL_WHEEL`/hi-res variants) — same interface, composited by the firmware |
| `piBrick PocketCM5 Keyboard System Control` | `event7` | HID "System Control" usage page (power/sleep/wake keys) |
| `piBrick PocketCM5 Keyboard Consumer Control` | `event8` | HID "Consumer Control" usage page (media keys) |

Because it's standard HID, it works out of the box under X11, labwc, or niri/Wayland — no udev rules or
custom driver needed for normal use. The one udev rule that *does* exist
(`/etc/udev/rules.d/99-vial.rules`, installed by `pibrick-driver`'s `install.sh`) only relaxes
`/dev/hidraw*` permissions for the logged-in user, so Vial's browser-based WebHID configurator can remap
keys without running as root.

### RP2040 GPIO pinout (from the firmware's `keyboard.json` / README)

| Function | GPIO |
|---|---|
| Key matrix columns | GP8, GP9, GP10, GP11, GP12, GP13 |
| Key matrix rows | GP1–GP7 (`COL2ROW` diode direction) |
| User Button 1 (left top) | GP24 |
| User Button 2 (left bottom) | GP17 |
| User Button 3 (right top) | GP0 |
| User Button 4 (right bottom) | GP15 |
| User Button 5 (rotary push switch) | GP20 |
| BBQ20 End/Hangup button | GP14 |
| Rotary encoder A / B | GP19 / GP21 (`resolution: 2`, i.e. 2 pulses per detent) |
| Keyboard backlight | GP25 (8 levels) |
| Panel/arrow-mode backlight indicator | GP29 |
| RGB indicator (R/G/B) | GP26 / GP27 / GP28 |
| Trackpad reset | GP16 |
| Trackpad motion (interrupt) | GP22 |
| Trackpad I2C (SCL/SDA) | GP23 / GP18 |

`rules.mk` enables `POINTING_DEVICE_ENABLE = yes` with `POINTING_DEVICE_DRIVER = custom` — a
custom QMK pointing-device driver for the BBQ20's I2C trackpad — plus `OLED_ENABLE`/`HAL_USE_I2C` on
the same I2C bus.

### Default keymap behavior (`keymaps/default/`)

Four layers, switched with a `SYM` key (single-shot: tap for one character then auto-return to Layer 0,
or hold to stay):

- **Layer 0** (default): letters. `LGui`/Super lives on the top panel. Modifiers (`ALT`/`CTRL`/`SHIFT`)
  use One-Shot-Mod (`OSM`) — tap once then press another key, or hold simultaneously. The trackpad's
  **Green/Call** button drag-scrolls, **Red/Hangup** right-clicks. The **Back** key is a tap-dance:
  tap → `ESC`, tap-and-hold → toggles the trackpad between mouse mode (static indicator) and arrow-key
  mode (blinking indicator, trackpad click becomes `ENTER`).
- **Layer 1**: symbols/numbers printed on the keycaps. `SYM` again → Layer 2, `Right Shift` → Layer 3.
- **Layer 2**: extended characters. Reachable directly from Layer 0 by double-tapping `SYM`.
- **Layer 3**: function/navigation keys. Reachable directly from Layer 0 via `SYM` then `Right Shift`.
- The rotary encoder changes keyboard backlight brightness when double-tap-and-held on `SYM`.

Fully remappable via [vial.rocks](https://vial.rocks) (talks to the `hidraw` device over WebHID); a
factory-default `.vil` keymap file ships in the firmware repo's `docs/` to restore from if a remap goes
wrong.

### Flashing (only needed to update/reflash the firmware itself)

Power off → hold **User Button 1** → plug the bottom USB-C port into a PC → device enumerates as a
`RPI-RP2` mass-storage drive (RP2040's native UF2 bootloader) → drag the built `.uf2` onto it → it
reboots automatically back into HID mode. `make pibrick_pocketcm5_keyboard:default` builds it (standard
QMK build).

## Relationship to this repo

This repo does not vendor or re-run `pibrick-driver`'s `install.sh` (kernel module build, dtbo install,
`/boot/firmware/config.txt` edits, `pibrick.service`/button setup) — that repo is the source of truth
for the hardware layer and is already installed and working on the device. This repo's Ansible
automation (`ansible/`) only manages the desktop/OS layer on top: dotfiles, VNC, and apt packages. See
[`docs/niri-dms-setup.md`](../docs/niri-dms-setup.md) for how the niri + DankMaterialShell desktop stack
on top of this hardware was built.
