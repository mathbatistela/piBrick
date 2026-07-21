# Terminal setup

zsh is the default interactive login shell (bash is kept installed and untouched for scripts —
`#!/bin/bash` is unaffected either way; only the human-facing shell changed). The stack layers a few
small, focused tools rather than a framework like Oh My Zsh, following what's currently the common
pattern for a fast, modern terminal: a Rust-based prompt/tool set on top of zsh's native plugin
mechanism, with no plugin manager.

## Components

| Tool | Purpose | Installed via |
|---|---|---|
| `zsh` | interactive shell | apt |
| `zsh-autosuggestions` | grey-text suggestions from history as you type | apt |
| `zsh-syntax-highlighting` | colors valid/invalid commands as you type (sourced last, per its own FAQ) | apt |
| `starship` | prompt | apt |
| `zoxide` | smarter `cd` — `z <fuzzy dir>` jumps by frecency | apt |
| `fzf` | fuzzy finder — `Ctrl-T` inserts a file path, `Alt-C` fuzzy-cd's into a subdirectory | apt |
| `atuin` | searchable shell history with context, takes over `Ctrl-R` (local SQLite, no account needed) | apt |
| `eza` | `ls` replacement (icons off, no Nerd Font installed) | apt |
| `bat` (binary: `batcat`) | `cat` replacement with syntax highlighting | apt |
| `fd-find` (binary: `fdfind`) | `find` replacement | apt |
| `yazi` | terminal file manager | mise (not in Debian's repos; too heavy to build on-device) |

Debian renames `bat` → `batcat` and `fd-find`'s binary → `fdfind` to avoid clashing with unrelated
existing packages of those names — `dotfiles/zsh/zshrc` aliases around it (`cat`, `fd`).

## No Nerd Font

The device has no Nerd Font installed, so `dotfiles/starship/starship.toml` deliberately avoids the
default preset's Powerline-style icon glyphs (they'd render as broken boxes) — just plain Unicode:
directory, git branch/status, and a green/red `❯`.

## Keybindings cheat sheet

| Key | Does |
|---|---|
| `Ctrl-R` | atuin: full-text, contextual history search |
| `Ctrl-T` | fzf: fuzzy-insert a file path at the cursor |
| `Alt-C` | fzf: fuzzy-cd into a subdirectory |
| `z <name>` | zoxide: jump to a frecent directory matching `<name>` |
| `Tab` | zsh's own completion menu (`menu select`) |

## yazi

`dotfiles/yazi/yazi.toml`:
- `sort_by = "mtime"` + `sort_reverse = true` — always newest-modified-first (directories still grouped
  first via `sort_dir_first`).
- `[opener] edit` overridden to `micro "$@"` — yazi's built-in file-type rules already route text files
  through the named `edit` opener, so overriding just that one opener was enough; no need to duplicate
  the routing rules.

## Files

| Path (repo) | Installed to | Applied by |
|---|---|---|
| `dotfiles/zsh/zshrc` | `~/.zshrc` | `ansible/roles/dotfiles/tasks/zsh.yml` |
| `dotfiles/starship/starship.toml` | `~/.config/starship.toml` | `ansible/roles/dotfiles/tasks/zsh.yml` |
| `dotfiles/yazi/yazi.toml` | `~/.config/yazi/yazi.toml` | `ansible/roles/dotfiles/tasks/yazi.yml` |
| — | default login shell → `/usr/bin/zsh` | `ansible/roles/dotfiles/tasks/zsh.yml` (`ansible.builtin.user`) |
| — | apt packages (table above) | `ansible/roles/packages/tasks/main.yml` |
| — | `yazi` via `mise use --global yazi` | `ansible/roles/packages/tasks/main.yml` |

`~/.config/mise/config.toml` (mise's own tool-version state, pinning `yazi`) is left unmanaged by
ansible, same reasoning as DMS's self-generated config fragments — it's tool-generated state, not
explicit config this repo authors.
