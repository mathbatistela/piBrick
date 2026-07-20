# dms-patches

Backups of local fixes applied on top of `~/dms` (a from-source clone of
[AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) built on the device —
see [`../docs/niri-dms-setup.md`](../docs/niri-dms-setup.md)). Those fixes only exist as **uncommitted
working-tree changes** in `~/dms` itself — not upstreamed, not committed there. This directory is their
real backup, and the mechanism for reapplying them whenever `~/dms` gets updated.

## Layout

- `manifest.json` — which DMS commit/version these were last applied against, plus a one-line
  description of what each patched file fixes
- `files/` — full copies of the patched files, mirroring their path under `~/dms` (e.g.
  `files/quickshell/Modules/AppDrawer/AppDrawerPopout.qml` → `~/dms/quickshell/Modules/AppDrawer/AppDrawerPopout.qml`)
- `apply.sh` — reapplies `files/*` over `~/dms`, rebuilds + reinstalls + restarts `dms` if anything
  changed, and updates `manifest.json`

This directory always holds the **current/latest** version of each patched file — not a history. If a
fix changes, overwrite the file in `files/` and update its description in `manifest.json`; don't keep
old versions around.

## Usage

Run **on the device itself** (needs `~/dms`, `make`, `sudo`, and the `dms` systemd user service):

```sh
~/piBrick/dms-patches/apply.sh
```

Idempotent — safe to run any time, not just after an update. It:
1. Compares `~/dms`'s current git commit against `manifest.json`'s `last_applied_dms_commit`
2. Diffs each file in `files/` against its counterpart in `~/dms`; copies over (overwriting) any that
   differ — this is what makes it survive a `git pull` in `~/dms`, which would otherwise silently revert
   these fixes back to the buggy upstream versions
3. If anything changed: `make build && sudo make install-bin`, `systemctl --user restart dms`
4. Updates `manifest.json` with the new commit/version/date

**After running this on the device**, if `manifest.json` changed, pull that update into this repo (it
was very likely run against `~/piBrick`, the device's own read-only HTTPS clone — see
[`../docs/agents/access.md`](../docs/agents/access.md) — so `manifest.json` needs to be copied back and
committed from a machine that can push, same as any other change originating on the device).

## Workflow for updating DMS

```sh
cd ~/dms && git pull        # may reintroduce the bugs these patches fix
~/piBrick/dms-patches/apply.sh   # detects the change, reapplies, rebuilds, reinstalls
```

If a patch no longer applies cleanly in the sense that its *purpose* seems already fixed upstream
(check `git log` on the relevant file in `~/dms` for a fix matching the description in `manifest.json`),
that patch may no longer be needed — remove it from `manifest.json` and `files/` rather than blindly
keep overwriting a file upstream has already fixed differently.

## Also worth doing

These are clean, minimal, well-isolated fixes following patterns already established elsewhere in DMS's
own codebase (see each fix's description). They're good upstream PR candidates against
`AvengeMedia/DankMaterialShell` — not done yet, but would remove the need for this whole mechanism for
whichever fixes land.
