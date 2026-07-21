#!/usr/bin/env bash
# Clones (or updates) the piBrick custom-driver repos into .reference/ for local source
# lookup. Untracked/gitignored — see the "Notes for future driver work" section in
# docs/hardware/pibrick-driver.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_DIR="$REPO_ROOT/.reference"
mkdir -p "$REF_DIR"

declare -A REPOS=(
  [pibrick-driver]="https://github.com/lshaf/pibrick-driver.git"
  [pibrick_pocketcm5_keyboard]="https://github.com/amarullz/pibrick_pocketcm5_keyboard.git"
)

for name in "${!REPOS[@]}"; do
  dest="$REF_DIR/$name"
  if [ -d "$dest/.git" ]; then
    echo "Updating $name..."
    git -C "$dest" pull --ff-only
  else
    echo "Cloning $name..."
    git clone --depth 1 "${REPOS[$name]}" "$dest"
  fi
done
