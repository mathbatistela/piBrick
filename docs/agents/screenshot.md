# Screenshotting the device's screen

The device runs Wayland (either the stock labwc desktop or the custom niri session — see
`docs/setup/niri-dms-setup.md`), so there's no single always-right socket: figure out which session is
actually active first, then grab the shot from that socket.

## 1. Find the active Wayland socket

```sh
ssh mbatistela@192.168.1.99 "ls -la /run/user/1000/wayland-*; loginctl list-sessions --no-legend; ps aux | grep -E 'niri|labwc' | grep -v grep"
```

There can be more than one `wayland-N` socket alive at once (e.g. one from labwc, one from a niri
session reached via `dm-tool switch-to-greeter`). Match the socket to whichever compositor process is
actually running/foregrounded — `wayland-0` was labwc, `wayland-1` was niri, on this device, but that
numbering isn't guaranteed to stay put across reboots/logins.

## 2. Capture with grim

```sh
ssh mbatistela@192.168.1.99 "XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-<N> grim /tmp/screenshot.png"
```

`grim` and `slurp` are already installed on this device.

## 3. Pull it back and view it

```sh
scp mbatistela@192.168.1.99:/tmp/screenshot.png <local-path>.png
```

Then read the local PNG with an image-capable read tool.

## Alternative: VNC

For interactive back-and-forth (not just a one-off screenshot), it's often faster to just connect over
VNC instead — see `access.md` for the client-compatibility gotcha (macOS's built-in VNC client doesn't
work against this device's `wayvnc` config; use TigerVNC or similar).
