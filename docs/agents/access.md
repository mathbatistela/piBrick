# Accessing the device

- Host: `mbatistela@192.168.1.99` (hostname `piBrick`), on the local network
- Passwordless SSH key auth is set up from this Mac (`~/.ssh/id_ed25519` is in the Pi's
  `authorized_keys`). Plain `ssh mbatistela@192.168.1.99` should just work from here.
- If running from a machine that doesn't have that key yet, password auth is still enabled as a
  fallback — get the password from the user, don't guess or reuse one from elsewhere.
- Passwordless sudo is configured for `mbatistela`
  (`/etc/sudoers.d/mbatistela-nopasswd`, `NOPASSWD: ALL`) — `sudo <cmd>` works without a password
  prompt, which is what lets the Ansible roles run unattended.

## VNC

`wayvnc` is enabled and running (port 5900), covering whatever Wayland session is currently active
(labwc or niri — see `screenshot.md` for how sessions/sockets work on this device).

**Gotcha:** `wayvnc`'s config (`/etc/wayvnc/config`, mirrored in `dotfiles/wayvnc/config`) uses
`enable_auth=true` + `enable_pam=true` + TLS (VeNCrypt security type). **macOS's built-in Finder/Screen
Sharing VNC client does not support this** and will just say "Connection failed" even though the port is
reachable — this cost real debugging time once already. Use a client that supports VeNCrypt/TLS+PAM
instead: **TigerVNC viewer** (`brew install --cask tigervnc`, free, no account) or RealVNC Viewer (note:
the `realvnc-connect` Homebrew cask installs the subscription "RealVNC Connect" product, which requires
an account — avoid it, use TigerVNC).

## Cloning this repo onto the Pi itself

The GitHub repo is public, so a plain HTTPS clone works with no credentials:

```sh
ssh mbatistela@192.168.1.99 "git clone https://github.com/mathbatistela/piBrick.git ~/piBrick"
```

That gives `git pull` but not `git push` (no credentials configured on the device for that). If push
access from the device itself is ever needed, set up a key or token there rather than copying this
Mac's private key over.
