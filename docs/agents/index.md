# Agent docs

Operating guide for an AI agent (or a human moving fast) working on the piBrick device through this
repo. Read `README.md` and `hardware/overview.md` at the repo root first for what the device *is*; this
folder is about *how to do things* to it.

- [`scope-and-safety.md`](scope-and-safety.md) — what this repo manages vs. doesn't, and which actions
  need user confirmation first
- [`access.md`](access.md) — reaching the device: SSH, sudo, VNC, and a gotcha or two
- [`ansible-workflow.md`](ansible-workflow.md) — running the playbook, dry-runs, dotfiles-are-source-
  of-truth, adding a new dotfile
- [`screenshot.md`](screenshot.md) — grabbing a screenshot of whatever's on the device's screen

The root `CLAUDE.md` is a short pointer into this folder — start there, it'll route you to the right
file.
