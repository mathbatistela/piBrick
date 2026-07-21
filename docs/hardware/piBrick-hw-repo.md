# piBrick (amarullz/piBrick) — repo reference

[amarullz/piBrick](https://github.com/amarullz/piBrick): the upstream **hardware design** repo — the
actual product/case/PCB source for the Pocket-CM5, as opposed to the driver or keyboard-firmware code.
Cloned on the device at `~/pi_brick/piBrick`, GPLv3 licensed. This doc is a repo-structure reference;
see [`overview.md`](overview.md) for the device's technical/electrical behavior.

## What's actually in the repo

The repo root is just a pointer README; everything lives under `Pocket-CM5/` (the only product
published so far — the repo is structured to hold more than one piBrick product eventually, per its
own README: "piBrick is Open Source Hardware project(s)").

**Not in the repo** (upstream, that is): the PCB/schematic itself lives externally on
[OSHWLab](https://oshwlab.com/amarullz/pibrick-pocketcm5) (EasyEDA Pro), linked from the README —
upstream doesn't vendor it as files, only the mechanical/case design and product collateral. This
admin repo, however, *does* keep a manually-exported PDF snapshot of the schematic under
[`docs/hardware/schematics/`](schematics/README.md) — a deliberate, narrow exception (same shape as
the `dms-patches/` exception in `docs/agents/scope-and-safety.md`), added because OSHWLab's JS
canvas editor can't be fetched or grepped for electrical detail. OSHWLab remains the source of
truth for anything newer than that snapshot.

| Path | Contents |
|---|---|
| `Pocket-CM5/README.md` | Full spec sheet, peripherals list, links, resources, demo videos — the canonical source for the spec bullets in `docs/hardware/overview.md` |
| `Pocket-CM5/3d/sketchup/` | SketchUp (`.skp`) source files for the case: current production design (`pibrick-pocketcm5-prod.skp`, `-prod-topmodify.skp`), design variants (`-design.skp`, `-clip-glass-display.skp`, `-design-glass-display.skp`), 2nd-batch/MagSafe variants, antenna/fan enclosures, and `extras/` (assembly jigs: `10pin-bend-jig.skp`, `display-jig.skp`) |
| `Pocket-CM5/3d/*.skp` (repo root of `3d/`) | Thread-insert case variants (`-noglue`, `-fdm`, plain) and the 2nd-batch MagSafe `.skp` |
| `Pocket-CM5/3d/stl/` | Exported STLs for printing, organized by purpose: `jlc3dp-0995-resized/` (parts scaled ×0.995 to compensate for JLC3DP's printer tolerance), `accessories/` (antenna-fan enclosure, bend/display jigs), `126280-Battery/` (case variant for a 126280-size cell), `legacy/` (three prior design generations: `old-design/`, `v1/`, `1st-batch-design/`, plus a `3d-stl.zip` bundle) |
| `Pocket-CM5/product/packaging/` | Retail packaging art — sticker/seal designs as Affinity Designer source (`.afdesign`) with matching print-ready `.pdf` exports |
| `Pocket-CM5/docs/images/` | README images: `cover.jpeg`, `showcase.png`, `piBrick-3d-showcase.png`, `pibrick--map.png` (port/button map), `oshw.png` (OSHWA certification badge), `sponsors.png`, `im1.jpg` |

## Case design history (from `3d/stl/legacy/`)

The STL tree preserves prior case revisions rather than deleting them: `legacy/old-design/` (earliest,
separate `face.stl`/`back.stl`/`button.stl`/`switch.stl` parts) → `legacy/v1/` → `legacy/` root (added
MagSafe back variant, consolidated switches) → current `stl/` root and `jlc3dp-0995-resized/` (current
production, scale-corrected for the manufacturer). Recent commits (`no-glue display design`, `Add camera
holder model`, `3D Models & Design Update` adding the fan enclosure + JIGs) show this is still actively
evolving.

## Relationship to this repo

Same as `pibrick-driver` and the keyboard firmware: this is a reference, not something this admin repo
vendors, builds, or automates. If you're touching the physical case (ordering a print, picking a
variant), `Pocket-CM5/3d/` on the device (or the upstream repo directly) is the source of truth, not
anything here.

**Exception**: [`docs/hardware/schematics/`](schematics/README.md) does vendor a PDF export of the
schematic itself, checked in directly to this repo rather than just linked — see that directory's
README for what's covered and why.
