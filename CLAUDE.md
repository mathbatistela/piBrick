# Agent guide

This repo manages a physical device: a piBrick Pocket-CM5 handheld at `mbatistela@192.168.1.99`
(hostname `piBrick`), reachable over SSH with key auth already configured from the machine this repo
was first set up on. Read `README.md` and `hardware/overview.md` first — they cover what the device is
and what already runs on it.

## Reaching the device

```sh
ssh mbatistela@192.168.1.99
```

If key auth isn't set up from the current machine, password auth is available (get the password from
the user — do not guess or reuse one from elsewhere without asking).

## Scope: what this repo manages vs. doesn't

- **Manages** (via `ansible/`): dotfiles (`~/.config/niri/`, `~/.bashrc`, `/etc/wayvnc/config`), VNC
  enablement, apt packages for the desktop stack.
- **Does not manage**: the kernel drivers (display/touch/battery/buttons) or keyboard firmware — those
  live in `pibrick-driver` and `pibrick_pocketcm5_keyboard` (both cloned under `~/pi_brick/` on the
  device itself, separate from this repo). Don't reimplement their install steps here; link to them.
- **Does not manage**: `niri`/`quickshell`/`dms`/`matugen`/`dgop`/`dsearch`, which are built from source
  on the device (see `docs/niri-dms-setup.md`). This repo captures their *config* (dotfiles) but not
  their source or build process — those are upstream repos with their own history, checked out under
  `~/src/` and `~/dms` on the device.

## Making changes

- Dotfiles in `dotfiles/` are the source of truth; the copies on the device are applied *from* here via
  the `dotfiles` Ansible role, not edited by hand on the device and never synced back automatically. If
  you change something live on the device and want to keep it, pull it back into `dotfiles/` explicitly
  (`scp`), same as how it was first captured.
- Prefer extending the Ansible roles over one-off ad hoc SSH commands for anything meant to persist —
  that's the point of this repo (repeatable, re-runnable config).
- Treat actions on the device with the same care as production infra: it's a physical device the user
  carries and uses daily. Reversible/local changes (editing a dotfile, running `--check`) are fine
  proactively; anything that reboots the device, changes boot config, or touches the kernel driver/boot
  partition should be confirmed with the user first.

## Verifying changes

`ansible-playbook -i ansible/inventory.ini ansible/site.yml --check` for a dry run before applying for
real. There's no CI here — the device itself is the only "test environment."
