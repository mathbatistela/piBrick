# Scope and safety

## What this repo manages

Via `ansible/` (see [`ansible-workflow.md`](ansible-workflow.md)):

- Dotfiles: `~/.config/niri/`, `~/.bashrc`, `/etc/wayvnc/config`
- VNC enablement (`wayvnc` systemd service)
- apt packages for the desktop stack (`foot`, `fuzzel`, `cava`, `qt6ct`, `squeekboard`, `wayvnc`)

## What it does not manage

- **Kernel drivers** (display/touch/battery/buttons) — owned by
  [lshaf/pibrick-driver](https://github.com/lshaf/pibrick-driver), cloned on the device at
  `~/pi_brick/pibrick-driver`. Don't reimplement its `install.sh` here; link to it. See
  `docs/hardware/overview.md` for what it does.
- **Keyboard firmware** — owned by
  [amarullz/pibrick_pocketcm5_keyboard](https://github.com/amarullz/pibrick_pocketcm5_keyboard) (RP2040
  QMK/Vial), cloned at `~/pi_brick/pibrick_pocketcm5_keyboard`. Reflashing it is a manual physical
  procedure (see `docs/hardware/overview.md`), not something this repo automates.
- **The desktop stack's own source** — `niri`, `quickshell`, `dms`, `matugen`, `dgop`, `dsearch` are
  built from source on the device (see `docs/setup/niri-dms-setup.md`), each an upstream repo under `~/src/`
  and `~/dms` with its own git history. This repo captures their *config* as dotfiles, not their source
  or build process — **except** a small, explicit set of local bug fixes to `~/dms` itself, tracked in
  [`../../dms-patches/`](../../dms-patches/) (full file backups + a script to reapply them after a
  `~/dms` update). That's a deliberate, narrow exception, not a reversal of this rule — see that
  directory's README before adding to it.

## Safety

The device is physical hardware the user carries and uses daily — treat it like it matters, not like a
disposable VM.

**Fine to do proactively** (reversible, local, low blast-radius):
- Editing a dotfile in this repo
- Running `ansible-playbook ... --check` (dry run, no changes)
- Reading/inspecting the live device (`cat`, `find`, screenshotting, checking service status)

**Confirm with the user first:**
- Applying the playbook for real (`ansible-playbook` without `--check`) — even though every role is
  designed to be idempotent and low-risk, changes to a device the user is actively using should be
  their call on timing
- Running `dms-patches/apply.sh` when it's actually going to rebuild something (i.e. it detected a
  change) — it restarts the `dms` user service, which visibly kicks the user out of whatever they're
  doing in the desktop shell for a few seconds. Running it when it's a no-op (nothing to reapply) is
  fine proactively; the "will it rebuild" check itself is just a read
- Anything that reboots the device, edits `/boot/firmware/config.txt`, or touches the kernel
  driver/boot partition
- Modifying `sudoers` or SSH auth config beyond what's already set up (see `access.md`)
- `git push` — always ask before pushing, same as any other repo
