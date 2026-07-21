# Fan control — investigation notes and the `pibrick-fan` tool

The CPU fan is entirely managed by the mainline Linux `pwm_fan.ko` hwmon driver and the generic
thermal framework — no `pibrick-driver` code involved (see `docs/hardware/overview.md`'s "CPU fan" section
for the hardware facts: hwmon/cooling-device wiring, the trip/PWM table, hysteresis). This doc covers
*how manual control was figured out*, the safety incident that shaped its design, and how to use the
`pibrick-fan` CLI this repo installs.

## Investigation: finding a lever that actually holds

Two sysfs surfaces touch the same hardware, and only one of them is a reliable manual override:

- `hwmon3/pwm1` (raw 0–255 duty) — writing this directly *does* move the hardware instantly (confirmed:
  writing `0` dropped RPM to 0, writing `255` spiked it to ~9200 RPM), but the driver's own background
  loop resyncs it back toward whatever `cooling_device0/cur_state` maps to within about a second,
  observed stepping down in visible increments (`255 → 175 → 125` over ~600ms in one test). Not usable
  as a persistent override.
- `cooling_device0/cur_state` (0–4) — the value the driver and governor actually treat as authoritative.
  Writing this holds indefinitely *as long as nothing else changes it*, which made it the right lever —
  but led to the incident below.

## Incident: `thermal_zone0/mode` is not a safe auto/manual switch

The obvious-looking way to implement "pause automatic control, let me drive `cur_state` manually, then
hand it back" was `thermal_zone0/mode` (`enabled`/`disabled`). Tried it live:

1. Forced `cur_state=3`, wrote `disabled` to `thermal_zone0/mode` — the forced value held rock-solid
   (confirmed over 5+ seconds while temp drifted 57–60 °C), which looked like exactly the intended
   behavior.
2. Wrote `enabled` back, expecting the governor to resume normal tracking.
3. It didn't. Over the next 12+ seconds, temp climbed as high as 60.6 °C (past the second active trip)
   while `cur_state` sat frozen at whatever it was last forced to. The governor never resumed reacting
   to temperature on this zone again — not immediately, not after minutes, not after rewriting a trip
   point to try to force a re-evaluation. Only a **reboot** restored normal automatic behavior.

Root cause isn't fully confirmed (no dmesg errors were logged around the toggle), but the fix is simple
and now load-bearing: **never write `thermal_zone0/mode`**. It doesn't matter why it breaks reactivity;
what matters is it does, reliably, and the only recovery seen was a reboot.

## Second finding (post-reboot): `cur_state` only steps *up* on a real interrupt

With the governor confirmed working again after reboot, a follow-up test isolated a second, more
fundamental quirk that shapes the tool's design — not caused by the `mode` incident, since it reproduced
cleanly on a freshly-booted, never-touched zone:

- Forced `cur_state=0` while temp was 58–60 °C (comfortably above the 50 °C trip). Watched for 6+
  seconds: it never climbed back up on its own.
- Tried rewriting a trip point (`trip_point_1_temp`) to its own value, hoping to force a governor
  re-evaluation the way it can for some thermal drivers. No effect — `cur_state` stayed put.
- By contrast, *downward* correction happens without any special trigger — observed the fan settle from
  a higher state down to a lower one during ordinary idle cooling with no manual intervention at all.

Conclusion: on this hardware, `cur_state` only ever steps **upward** in response to a genuine hardware
trip-crossing interrupt from the temperature sensor. A software-only nudge (sysfs poke, waiting, trip
rewrite) does not substitute for one. Practical consequence: if `cur_state` is ever left lower than
current temperature warrants, it can stay there indefinitely, under-cooling the CPU — the 110 °C
critical trip is a hard backstop against real thermal damage (evaluated independently of `cur_state`,
still shuts the system down if reached), but nothing above that would step the fan back up on its own.

This is why `pibrick-fan auto` (below) does more than just stop overriding — it explicitly computes and
writes the `cur_state` the trip table says the *current* temperature warrants, as a one-time safe
handoff, before returning control to the kernel governor.

## The `pibrick-fan` tool

Installed to `/usr/local/bin/` by this repo's Ansible `dotfiles` role (`ansible/roles/dotfiles/tasks/fan.yml`,
source in `dotfiles/fan/`). Requires root (`sudo`) — it writes to `/sys/class/thermal/...` and controls a
systemd service.

```sh
sudo pibrick-fan status                          # show current mode, cur_state, pwm, rpm, temp
sudo pibrick-fan set <off|low|med|high|max|0-4>   # pin the fan to a level, ignoring temperature
sudo pibrick-fan auto                             # hand control back to the kernel governor, safely
```

### How `set` holds a level

`set` writes the chosen level to `/etc/pibrick/fan-level` and starts `pibrick-fan-manual.service`, which
runs `pibrick-fan-hold` — a tight loop (`dotfiles/fan/pibrick-fan-hold`) that re-writes
`cooling_device0/cur_state` from that file every 0.3s. That's faster than the governor's own correction
cadence (observed correcting within roughly 0.5–1s), so the pinned loop wins the fight and the level
holds. The kernel governor is never disabled while this runs — it keeps trying to reassert its own idea
of `cur_state`, it just loses, repeatedly, every 0.3s.

### How `auto` hands back control safely

Per the second finding above, just stopping the pin loop isn't enough — `cur_state` could be left below
what current temperature warrants, with no guarantee anything will step it back up soon. So `auto`:

1. Stops `pibrick-fan-manual.service`.
2. Reads live trip-point temps (`thermal_zone0/trip_point_{1,2,3,4}_temp`) and the current temp, computes
   the state the trip table indicates, and writes that to `cur_state` once.
3. From that accurate starting point, genuine future temperature changes generate their own trip-crossing
   interrupts and the kernel governor tracks correctly from there — this was verified live: pinned the fan
   off at ~58 °C, called `auto`, and watched `cur_state` correctly settle to 2 and keep tracking real temp
   fluctuations (56–59.5 °C) over the following 10 seconds with no further manual intervention.

### Safety notes

- The `110 °C` critical shutdown trip is independent of all of the above (evaluated directly by the
  thermal core, not through the cooling-device/governor path) — it still protects the hardware even
  while a manual level is pinned.
- `pibrick-fan-manual.service` is not enabled at boot and does not persist across a reboot — a reboot
  always comes back up in plain kernel-automatic mode.
- Never write `thermal_zone0/mode` directly (see incident above) — if you ever find the fan stuck
  unresponsive to temperature and `pibrick-fan auto` doesn't fix it, a reboot is the known-working
  recovery.

## Files

| Path (repo) | Installed to | Purpose |
|---|---|---|
| `dotfiles/fan/pibrick-fan` | `/usr/local/bin/pibrick-fan` | CLI: `status` / `set` / `auto` |
| `dotfiles/fan/pibrick-fan-hold` | `/usr/local/bin/pibrick-fan-hold` | Loop that pins `cur_state`, run by the service below |
| `dotfiles/fan/pibrick-fan-manual.service` | `/etc/systemd/system/pibrick-fan-manual.service` | systemd unit wrapping `pibrick-fan-hold`; started/stopped by the CLI, not enabled at boot |
| `ansible/roles/dotfiles/tasks/fan.yml` | — | Ansible task file that installs the three files above |
