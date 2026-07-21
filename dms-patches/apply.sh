#!/bin/bash
# Reapply piBrick's local DMS fixes on top of whatever's currently in ~/dms, then
# rebuild + reinstall + restart if anything changed. Run this ON THE DEVICE (not
# from a control machine) after any `git pull` in ~/dms, and any time you want to
# confirm the fixes are still in place. Idempotent: safe to run repeatedly.
#
# See docs/setup/niri-dms-setup.md for what each patched file fixes and why.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMS_DIR="${DMS_DIR:-$HOME/dms}"
MANIFEST="$SCRIPT_DIR/manifest.json"

if [ ! -d "$DMS_DIR" ]; then
    echo "!!! $DMS_DIR not found. Set DMS_DIR if it lives elsewhere." >&2
    exit 1
fi

current_commit="$(git -C "$DMS_DIR" rev-parse HEAD)"
last_commit="$(python3 -c "import json; print(json.load(open('$MANIFEST'))['last_applied_dms_commit'])")"

if [ "$current_commit" != "$last_commit" ]; then
    echo ">>> ~/dms has moved since these fixes were last applied/verified:"
    echo "    last applied against: $last_commit"
    echo "    currently at:         $current_commit"
    echo ">>> Reapplying our patched files over whatever upstream shipped for them."
else
    echo ">>> ~/dms is at the same commit these fixes were last applied against ($current_commit)."
fi

changed=0
mapfile -t rel_paths < <(python3 -c "
import json
for f in json.load(open('$MANIFEST'))['files']:
    print(f['path'])
")

for rel_path in "${rel_paths[@]}"; do
    src="$SCRIPT_DIR/files/$rel_path"
    dest="$DMS_DIR/$rel_path"
    if [ ! -f "$src" ]; then
        echo "!!! Missing backup for $rel_path in dms-patches/files/ - skipping." >&2
        continue
    fi
    if [ ! -f "$dest" ]; then
        echo "!!! $dest doesn't exist upstream anymore - upstream may have moved/renamed this file. Skipping, needs manual review." >&2
        continue
    fi
    if cmp -s "$src" "$dest"; then
        echo "    ok (already applied): $rel_path"
    else
        cp "$src" "$dest"
        echo "    patched:               $rel_path"
        changed=1
    fi
done

if [ "$changed" -eq 0 ] && [ "$current_commit" == "$last_commit" ]; then
    echo ">>> Nothing to do - all patches already applied, DMS unchanged since last run."
    exit 0
fi

echo ">>> Rebuilding and reinstalling dms..."
(cd "$DMS_DIR" && make build)
(cd "$DMS_DIR" && sudo make install-bin)
systemctl --user restart dms

new_commit="$(git -C "$DMS_DIR" rev-parse HEAD)"
new_version="$(cd "$DMS_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")+git$(cd "$DMS_DIR" && git rev-list --count HEAD)"
python3 -c "
import json
p = '$MANIFEST'
d = json.load(open(p))
d['last_applied_dms_commit'] = '$new_commit'
d['last_applied_dms_version'] = '$new_version'
d['last_applied_date'] = __import__('datetime').date.today().isoformat()
json.dump(d, open(p, 'w'), indent=2)
open(p, 'a').write('\n')
"
echo ">>> Done. Manifest updated to commit $new_commit ($new_version)."
echo ">>> Remember to commit dms-patches/manifest.json in the piBrick repo if this ran on the device's own clone."
