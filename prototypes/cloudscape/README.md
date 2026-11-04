# Solarized cloudscape study

A dependency-free WebGL visual prototype and optional native trial.
The permanent desktop service now lives in `home/damon/cloudscape/`; see its
README for Home Manager integration and lifecycle policy. The browser study
remains standalone.

## Run

Open `index.html` in a WebGL-capable browser, or from the repository root:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory prototypes/cloudscape
```

Visit <http://localhost:8080>. Stop the server with Ctrl-C.

## Native Papertoy trial (Niri / NixOS)

From the repository root:

```sh
python3 prototypes/cloudscape/try-papertoy.py
# Or choose a fixed palette (do not follow Darkman):
python3 prototypes/cloudscape/try-papertoy.py --mode dark
```

The launcher builds Papertoy at revision
`8ad06cf9f22c34018859c51b07a3e2d0b8d28701`, with the local palette patch.
The launcher builds the root flake's `cloudscape-renderer` package, sharing the
production patches and nixpkgs pin. This avoids the older upstream libc failing
to load the current system Mesa driver (`EglBadDisplay`, with a loader error for
`GLIBC_ABI_GNU2_TLS`). Running the trial does not activate Home Manager changes.
If the permanent service is active, stop `cloudscape.service` first, then start
it again after exiting the trial. A shared lock prevents concurrent renderers.

It extracts the shader and drift/contrast defaults directly from `index.html`,
converts its entry point to Shadertoy, and runs one process per enabled output.
Default rendering is 300px high, aspect-correct, at 30 fps. On the current two
16:9 monitors this is 533×300 per output. Each process has its own animation
clock; this is not a synchronized panorama.

**The trial temporarily stops `awww` globally.** Ctrl-C, SIGTERM, or a detected
renderer failure terminates the renderers, restarts `awww` if it was previously
active, and restarts the active theme watcher to reapply the current wallpaper.
No services are enabled or disabled. If the launcher is forcibly killed with
SIGKILL, recover manually:

```sh
systemctl --user start awww-daemon.service
systemctl --user restart waybar-theme-watcher.service
```

Optional arguments: `--output DP-8` (repeatable), `--height 300`, `--fps 15`,
`--binary /path/to/patched-papertoy`. A binary override must include our patch.
Selecting one output still stops `awww` on all
outputs, so unselected outputs will have no wallpaper during the trial.
Use `--mode light --print-shader` to inspect the generated GLSL without starting
anything.

### Live palette control

By default, the launcher polls Darkman once per second and atomically publishes
changes to a private text file. Each patched renderer polls that file about four
times a second while rendering. The `uDark` uniform eases toward 0 (light) or 1
(dark), with the browser's 0.8-second exponential time constant (mostly changed
after about 2.4 seconds, settled after about 5.5 seconds). Animation time and
renderer processes are untouched. Initial palette is applied immediately to
avoid a light flash on a dark desktop. Missing/invalid values retain the last
valid target. Darkman failures are retried without stopping the wallpaper.

For a wallpaper-only test that does not change application themes:

```sh
printf 'light\n' > "$XDG_RUNTIME_DIR/cloudscape-palette"
python3 prototypes/cloudscape/try-papertoy.py \
  --palette-file "$XDG_RUNTIME_DIR/cloudscape-palette"
# In a second terminal:
printf 'dark\n' > "$XDG_RUNTIME_DIR/cloudscape-palette.tmp"
mv "$XDG_RUNTIME_DIR/cloudscape-palette.tmp" "$XDG_RUNTIME_DIR/cloudscape-palette"
# Repeat with light to switch back.
```

The host's control interface is the `PAPERTOY_PALETTE_FILE` environment variable;
`home/damon/cloudscape/palette.zig` implements parsing, polling, and blending.
The adjacent `papertoy-palette.patch` connects it to the uniform buffer without
changing upstream's clock. The permanent service uses the existing theme watcher
to publish the palette directly, removing the trial launcher's Darkman polling.

**Limitations:** no hotplug management, explicit lock/display-off policy, or
power measurements yet. Exit the trial before changing the monitor layout.
The browser's reduced-motion handling is not implemented in the native trial.

Validation: four Zig tests run during the Nix build (parsing, blending, low-FPS
behavior, file changes and failure retention). Python adapter/publication tests:

```sh
python3 -B -m unittest discover -s prototypes/cloudscape -p 'test_*.py'
```

A native two-output smoke test changed the palette file light → dark → light,
confirmed unchanged renderer PIDs, then verified SIGTERM cleanup restored both
existing services. Both fixed palettes and live Darkman switching were visually
approved before the permanent-service integration.

## Art direction and controls

Distinct, softly shaded cloud banks inspired by low-resolution older desktop
wallpapers, rather than photorealistic volumetric clouds. Five-octave procedural
noise is warped slowly, with broad density shading and directional highlights.
A fainter layer drifts at a different speed behind the main clouds.

- **Render height:** defaults to 300 pixels, smoothly upscaled by the browser.
  Try 240 for softer legacy-wallpaper character or 540 for more detail.
  This intentionally ignores display pixel density to limit rendering cost.
- **Cloud definition:** defaults to 0.4×, for low contrast around a quiet
  palette-specific color.
- **Drift:** defaults to 0.2× for subtle movement; try 3× to evaluate motion quickly.
- **D:** blend between Solarized light and dark without resetting the clouds.
- **Space:** freeze cloud motion (palette transitions still work).
- **H:** hide/show controls; a small reveal button remains available.

The initial palette follows the browser's system color scheme and continues to
follow changes until manually toggled. Reload to return to automatic selection.
Reduced-motion preference starts the scene paused and makes palette changes
instantaneous. Rendering is capped at 30 fps; hidden tabs do not advance the
simulation. Paused, settled frames are not redrawn.

## Evaluate

1. Hide the controls and let the default sky run for a minute. Does it read as
   clouds rather than smoke? Is movement too noticeable?
2. Compare 240/360/540-pixel rendering heights, especially on a large monitor.
3. Pause, then toggle palettes: silhouettes should stay in exactly the same place.
4. Resize the window: cloud proportions should remain stable, with more sky
   revealed horizontally on wider windows.
5. Check light and dark behind ordinary application windows before settling on
   contrast. Browser fullscreen can help approximate the wallpaper experience.

The hex Solarized colors are shader anchors, not a restriction to discrete colors.
This is an artistic approximation, not a physically based atmospheric model.
GPU/power use has not yet been measured. The native trial establishes Wayland
hosting and live palette control. Permanent theme-watcher integration, output
supervision, and lock/display-off handling now live in `home/damon/cloudscape/`.
