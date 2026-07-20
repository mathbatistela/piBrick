# piBrick

Admin repo for my [piBrick Pocket-CM5](https://github.com/amarullz/piBrick) handheld: hardware context,
OS/desktop dotfiles, and Ansible automation to configure the device over SSH (or run locally on the
device itself).

- `hardware/overview.md` — what the interactable hardware is and how the drivers use it (display,
  touch, battery, buttons, keyboard/trackpad/scroll-wheel)
- `docs/niri-dms-setup.md` — build log for the custom niri + DankMaterialShell desktop stack running
  on this device
- `docs/pibrick-driver.md`, `docs/piBrick-hw-repo.md` — repo-structure references for the two upstream
  hardware repos (kernel drivers; case/PCB design)
- `docs/agents/` — operating guide for an agent working on this device: access, safety rules, the
  Ansible workflow, screenshotting
- `dotfiles/` — live-pulled OS/desktop config (niri, bash, wayvnc, foot, autostart)
- `ansible/` — playbook + roles to apply `dotfiles/`, enable VNC, install the desktop-stack apt
  packages, and keep the GTK theme (adw-gtk3) matching DMS, idempotently
- `dms-patches/` — backups of local bug fixes applied on top of the from-source `~/dms`
  (DankMaterialShell) checkout, versioned against the DMS commit they apply to, with a script to
  reapply them after any `~/dms` update

Kernel driver install (display/touch/battery/button) and the keyboard firmware are **not** managed
here — see [lshaf/pibrick-driver](https://github.com/lshaf/pibrick-driver) and
[amarullz/pibrick_pocketcm5_keyboard](https://github.com/amarullz/pibrick_pocketcm5_keyboard), both
already checked out on the device under `~/pi_brick/`.

## Device

- Host: `mbatistela@192.168.1.99` (hostname `piBrick`), SSH key auth already set up from this Mac
- OS: Raspberry Pi OS (Debian 13 trixie, arm64) on a CM5
- `mbatistela` has passwordless sudo (`/etc/sudoers.d/mbatistela-nopasswd`, `NOPASSWD: ALL`), needed
  for the `packages` and `vnc` roles to run unattended

## Running the playbook

From a control machine (e.g. this Mac), over SSH:

```sh
cd ansible
ansible-playbook -i inventory.ini site.yml
```

Add `--check` for a dry run.

Running it **locally on the Pi itself** instead: use the `local` inventory group (see
`inventory.ini`), which sets `ansible_connection=local`:

```sh
ansible-playbook -i inventory.ini site.yml --limit local
```

## Requirements

Control machine needs `ansible` (`brew install ansible` on macOS). The target needs Python 3 (already
present on Raspberry Pi OS).
