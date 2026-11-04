#!/usr/bin/env python3
"""Temporary native wallpaper trial; no persistent desktop configuration changes."""

import argparse
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent


def shader_source():
    # Keep the browser study as the source of truth for the cloud mathematics.
    html = (HERE / "index.html").read_text()
    source = html.split("const fragment = `", 1)[1].split("`;", 1)[0]
    speed = re.search(r'id="speed"[^>]*value="([\d.]+)"', html)[1]
    contrast = re.search(r'id="contrast"[^>]*value="([\d.]+)"', html)[1]
    replacements = {
        "precision highp float;": "// Adapted from the browser study for Shadertoy/Papertoy.",
        "uniform vec2 resolution;": "#define resolution iResolution.xy",
        "uniform float time;": f"#define time (iTime * {float(speed)})",
        "uniform float dark;": "#define dark uDark",
        "uniform float definition;": f"const float definition = {float(contrast)};",
        "void main() {": "void mainImage(out vec4 fragColor, in vec2 fragCoord) {",
        "gl_FragCoord.xy": "fragCoord",
        "gl_FragColor": "fragColor",
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise ValueError(f"Browser shader changed: expected exactly one {old!r}")
        source = source.replace(old, new)
    return source


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def active(unit):
    return subprocess.run(
        ["systemctl", "--user", "is-active", "--quiet", unit]
    ).returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    palette_args = parser.add_mutually_exclusive_group()
    palette_args.add_argument("--mode", choices=["light", "dark"], help="fixed palette; default: follow Darkman live")
    palette_args.add_argument("--palette-file", type=Path, help="read light/dark from this file instead of Darkman")
    parser.add_argument("--output", action="append", help="Niri output name; repeatable, default: all enabled outputs")
    parser.add_argument("--height", type=int, default=300, help="render height (default: 300)")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--print-shader", action="store_true", help="print the ported shader without starting anything")
    parser.add_argument("--binary", type=Path, help="use an already-built palette-patched Papertoy binary")
    args = parser.parse_args()
    if not 60 <= args.height <= 2160 or not 1 <= args.fps <= 120:
        parser.error("height must be 60–2160; fps must be 1–120")
    source = shader_source()
    if args.print_shader:
        print(source)
        return
    if args.palette_file:
        args.palette_file = args.palette_file.resolve()
        mode = args.palette_file.read_text().strip()
    else:
        mode = args.mode or read_darkman()
    if mode not in ("dark", "light"):
        raise ValueError(f"Unexpected initial palette: {mode!r}")
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Run this from a terminal inside your Niri session.")
    outputs = json.loads(run("niri", "msg", "--json", "outputs", capture_output=True).stdout)
    names = args.output or sorted(name for name, info in outputs.items() if info["logical"])
    if not names or len(set(names)) != len(names):
        raise ValueError("Select at least one enabled output, without duplicates.")
    sizes = {}
    for name in names:
        if name not in outputs or not outputs[name]["logical"]:
            raise ValueError(f"Output {name!r} is not enabled.")
        logical = outputs[name]["logical"]
        width = math.floor(args.height * logical["width"] / logical["height"] + 0.5)
        sizes[name] = f"{width}x{args.height}"
    # Build before touching the running wallpaper. No root-flake changes or result symlink.
    binary = args.binary
    if binary is None:
        print("Building palette-patched Papertoy (cached after the first run)…", flush=True)
        store = run(
            "nix", "build", f"path:{HERE.parent.parent}#cloudscape-renderer",
            "--no-write-lock-file", "--no-link", "--print-out-paths",
            capture_output=True,
        ).stdout.strip()
        binary = Path(store) / "bin/papertoy"
    binary = binary.resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError(f"Not an executable: {binary}")

    # Prevent concurrent trials from restoring each other's wallpaper daemon.
    import fcntl
    lock_path = Path(os.environ["XDG_RUNTIME_DIR"]) / "cloudscape-wallpaper.lock"
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Cloudscape is already running. Stop cloudscape.service before starting a trial.") from None
        trial(binary, source, mode, sizes, args.fps,
              follow_darkman=args.mode is None and args.palette_file is None,
              palette_file=args.palette_file)


def read_darkman():
    mode = run("darkman", "get", capture_output=True, timeout=2).stdout.strip()
    if mode not in ("dark", "light"):
        raise ValueError(f"Unexpected Darkman mode: {mode!r}")
    return mode


def write_palette(path, mode):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(mode + "\n")
    temporary.replace(path)


def trial(binary, source, mode, sizes, fps, *, follow_darkman=False, palette_file=None):
    children = []
    restore_awww = active("awww-daemon.service")
    refresh_theme = active("waybar-theme-watcher.service")
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    with tempfile.TemporaryDirectory(prefix="cloudscape-") as directory:
        shader = Path(directory) / "clouds.glsl"
        shader.write_text(source)
        if palette_file is None:
            palette_file = Path(directory) / "palette"
            write_palette(palette_file, mode)
        environment = dict(os.environ, PAPERTOY_PALETTE_FILE=str(palette_file))
        next_poll = 0.0
        palette_warning = False
        try:
            if restore_awww:
                run("systemctl", "--user", "stop", "awww-daemon.service")
            if stopping:
                return
            for output, size in sizes.items():
                print(f"{output}: {size}, {fps} fps, {mode} palette", flush=True)
                children.append(subprocess.Popen([
                    str(binary), "--output", output, "--resolution", size,
                    "--frame-rate", str(fps), str(shader),
                ], start_new_session=True, env=environment))
            print("Cloudscape trial running. Ctrl-C restores the previous wallpaper service.", flush=True)
            print("Palette: " + ("following Darkman" if follow_darkman else str(palette_file)), flush=True)
            print("Monitor hotplug is not supported yet.", flush=True)
            while not stopping:
                if follow_darkman and time.monotonic() >= next_poll:
                    try:
                        updated = read_darkman()
                        if updated != mode:
                            write_palette(palette_file, updated)
                            mode = updated
                            print(f"Blending to {mode}", flush=True)
                        palette_warning = False
                    except (OSError, ValueError, subprocess.SubprocessError) as error:
                        if not palette_warning:
                            print(f"Retaining palette; Darkman unavailable: {error}", file=sys.stderr)
                        palette_warning = True
                    next_poll = time.monotonic() + 1.0
                for child in children:
                    if child.poll() is not None:
                        raise RuntimeError(f"Papertoy exited unexpectedly ({child.returncode}).")
                time.sleep(0.2)
        finally:
            for child in children:
                if child.poll() is None:
                    child.terminate()
            for child in children:
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            if restore_awww:
                # Separate attempts: a failed start must not prevent a theme refresh.
                subprocess.run(["systemctl", "--user", "start", "awww-daemon.service"], check=False)
                if refresh_theme:
                    subprocess.run(["systemctl", "--user", "restart", "waybar-theme-watcher.service"], check=False)
                print("Restored wallpaper service; theme watcher reapplies the current palette.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"cloudscape: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
