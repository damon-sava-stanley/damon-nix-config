# Solarized cloudscape wallpaper

The permanent Home Manager wallpaper service replaces `awww`, using the approved
procedural cloud shader: drift **0.2**, definition **0.4**, render height **300px**,
**30 fps**. Each enabled output gets an aspect-correct low-resolution buffer,
upscaled by Niri. Outputs have independent animation clocks, not a panorama.

## Components

- `default.nix`: graphical-session service, ordered after the theme watcher.
- `supervisor.py`: output reconciliation, lock/power policy, isolated child retries.
- `clouds.glsl`: native version of the browser study. A test compares it against
  the prototype conversion to prevent accidental visual divergence.
- `palette.zig` / `papertoy-palette.patch`: live `uDark` uniform. The existing theme
  watcher atomically writes `~/.cache/theme-sync/cloudscape`; no second Darkman
  watcher is needed. Missing/invalid palette updates retain the last good target.
- `papertoy-viewport.patch`: custom-resolution rendering fills the compositor's
  configured logical size, including scale-1 and rotated outputs. The viewport
  is initialized on the first layer-shell configure rather than waiting for a
  scale change.
- `../packages/cloudscape-renderer.nix`: pinned upstream renderer with patches
  and four build-time Zig tests. The root flake owns the Papertoy input, following
  its nixpkgs to avoid libc/Mesa incompatibility.

## Lifecycle and power policy

Every second, the supervisor reconciles `niri msg --json outputs` with its children.
An output with no logical configuration is disabled. New/enabled outputs get a
renderer; removed/disabled outputs lose theirs. Dimension, scale, mode, or
transform changes restart only the affected renderer. Unexpected crashes use
per-output exponential backoff (1–30 seconds), resetting after a minute of stable
running. Losing compositor state stops renderers until a valid snapshot returns.
Zero enabled outputs is normal, not a service failure.

Niri 26.04 does **not** provide lock/DPMS events in its IPC event stream. On this
Linux/Niri/swaylock setup we instead check:

- `/proc`: any `swaylock` process owned by this user stops all wallpaper renderers.
  This covers the existing keybinding, idle lock, and before-sleep paths without
  modifying security-sensitive locking or daemonization behavior.
- `/sys/class/drm/card*-OUTPUT/dpms`: `Off` stops that output's renderer. Actual
  Niri power-off/on behavior was verified against these files on this machine.
  Unknown/non-DRM outputs remain renderable. On multi-GPU systems with duplicate
  connector names, any non-Off match wins; such systems need separate validation.

This is resource management, **not a lock security boundary**. Detection may lag
by about one polling interval. Different lock programs need explicit support.
There are no SIGSTOP-frozen Wayland clients. Stopping the renderers eliminates
their GPU work while hidden by the lock or powered off; the small supervisor
continues polling. Unlock cannot resume an output that remains powered off, and
power-on cannot resume while swaylock is still running.

After unlock/display-on, cloud positions restart. Live palette changes do **not**
restart the renderer or its animation. Physical unplug/replug also restarts that
output. There is no window-occlusion heuristic: visible wallpaper continues to
animate even when other windows are open. GPU/power consumption while visible
has not yet been benchmarked.

## Deploy and operate

Build the host, then activate through the normal NixOS rebuild workflow. If new
files have not yet been staged in Git, use a `path:` flake so Nix includes them:

```sh
nix build "path:$PWD#checks.x86_64-linux.cloudscape" --no-link
sudo nixos-rebuild switch --flake "path:$PWD#deeley"
systemctl --user status cloudscape.service
journalctl --user -u cloudscape.service -f
```

No compositor restart is required. The old `awww` unit is removed by Home Manager,
and the new service also conflicts with it to avoid two background owners during
migration. The theme watcher remains the single source of desktop palette state.

To disable the animation temporarily:

```sh
systemctl --user stop cloudscape.service
# Niri's configured solid background remains.
systemctl --user start cloudscape.service
```

The prototype trial and permanent service share a singleton lock. Stop the
service before running `prototypes/cloudscape/try-papertoy.py`; start it again
when finished. The trial does not automatically restore the permanent service.

To revert the entire migration, switch to the preceding NixOS generation. Simply
starting the removed `awww` service is not a persistent rollback strategy.

## Validation

- Four Zig palette tests in the renderer build.
- Twelve Python lifecycle/sensor tests (`python3 -B tests/cloudscape.py`).
- Four prototype/conversion/publication tests.
- Nix service-wiring assertions and the existing Waybar lifecycle check.
- Full NixOS toplevel build.
- Native smoke test on all three currently enabled outputs: stable renderer PIDs
  during palette change; actual global DPMS-off stopped every child; power-on
  recreated all three; shutdown cleaned up and restored the prior wallpaper.
- Wayland protocol trace confirmed configured logical viewport destinations
  (2560×1440 externals, 1440×960 laptop), with 300px-high render buffers.

Still verify after activation: manual lock/unlock, physical dock disconnect and
reconnect, `niri-toggle-monitors`, suspend/resume, and scale-1/rotated outputs.
The supervisor state-machine tests cover these transitions synthetically; they
are not substitutes for compositor/hardware testing.
