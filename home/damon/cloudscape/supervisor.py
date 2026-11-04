#!/usr/bin/env python3
"""Supervise one cloud renderer per enabled, powered Niri output.

Niri 26.04 has no lock/DPMS IPC events. Poll its output snapshot, Linux DRM
connector DPMS, and this user's swaylock processes. No changes to lock plumbing.
"""

import argparse
from dataclasses import dataclass
import fcntl
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def log(message):
    print(message, flush=True)


def swaylock_running(proc=Path("/proc"), uid=None):
    uid = os.getuid() if uid is None else uid
    for path in proc.iterdir():
        if not path.name.isdigit():
            continue
        try:
            if path.stat().st_uid == uid and (path / "comm").read_text().strip() == "swaylock":
                return True
        except (FileNotFoundError, ProcessLookupError):
            continue  # Process exited during the scan.
    return False


def powered(output, drm=Path("/sys/class/drm")):
    """Unknown/non-DRM outputs remain usable; verified Off outputs do not render.

    Connector names can repeat on multi-GPU systems. In that case an On match
    wins: avoid hiding a live output because an unrelated connector is off.
    """
    states = []
    for connector in drm.glob("card*-*"):
        if connector.name.split("-", 1)[1] != output:
            continue
        try:
            states.append((connector / "dpms").read_text().strip())
        except FileNotFoundError:
            continue
    return not states or any(state != "Off" for state in states)


def desired_outputs(outputs, *, locked, height=300, is_powered=powered):
    if locked:
        return {}
    desired = {}
    for name, output in outputs.items():
        logical = output.get("logical")
        if not logical or not is_powered(name):
            continue
        width, logical_height = logical["width"], logical["height"]
        if width <= 0 or logical_height <= 0:
            continue
        render_width = max(1, math.floor(height * width / logical_height + 0.5))
        # Include logical dimensions/scale/transform to recreate only affected
        # surfaces on mode changes (upstream cannot robustly handle hotplug).
        signature = (render_width, height, width, logical_height,
                     logical.get("scale"), logical.get("transform"), output.get("current_mode"))
        desired[name] = signature
    return desired


@dataclass
class Child:
    process: object
    signature: tuple
    started: float


class Supervisor:
    def __init__(self, spawn, stop, clock=time.monotonic):
        self.spawn = spawn
        self.stop = stop
        self.clock = clock
        self.children = {}
        self.failures = {}
        self.retry_at = {}

    def reconcile(self, desired):
        now = self.clock()
        for name, child in list(self.children.items()):
            if name not in desired or desired[name] != child.signature:
                self.stop(child.process)
                del self.children[name]
                self.failures.pop(name, None)
                self.retry_at.pop(name, None)
                log(f"Stopped {name}")
            elif child.process.poll() is not None:
                del self.children[name]
                if now - child.started >= 60:
                    self.failures.pop(name, None)
                self.failed(name, now, f"exit {child.process.returncode}")
        for name in set(self.failures) - desired.keys():
            self.failures.pop(name, None)
            self.retry_at.pop(name, None)
        for name, signature in desired.items():
            if name in self.children or now < self.retry_at.get(name, 0):
                continue
            try:
                process = self.spawn(name, signature)
            except OSError as error:
                self.failed(name, now, str(error))
                continue
            self.children[name] = Child(process, signature, now)
            log(f"Started {name} at {signature[0]}x{signature[1]}")

    def failed(self, name, now, reason):
        count = min(self.failures.get(name, 0) + 1, 6)
        self.failures[name] = count
        delay = min(2 ** (count - 1), 30)
        self.retry_at[name] = now + delay
        log(f"Renderer {name} failed ({reason}); retry in {delay}s")

    def close(self):
        self.reconcile({})


def stop_child(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    else:
        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderer", required=True)
    parser.add_argument("--shader", required=True)
    parser.add_argument("--palette-file", required=True, type=Path)
    parser.add_argument("--niri", default="niri")
    args = parser.parse_args()
    stopping = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stopping.set())
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    with (runtime / "cloudscape-wallpaper.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another cloudscape service or trial is already running.") from None
        environment = dict(os.environ, PAPERTOY_PALETTE_FILE=str(args.palette_file))

        def spawn(name, signature):
            return subprocess.Popen([
                args.renderer, "--output", name,
                "--resolution", f"{signature[0]}x{signature[1]}",
                "--frame-rate", "30", args.shader,
            ], env=environment)

        supervisor = Supervisor(spawn, stop_child)
        last_error = None
        palette_ready = False
        try:
            while not stopping.is_set():
                try:
                    # Wait for the theme watcher to publish a valid initial
                    # palette rather than flashing light on a dark desktop.
                    if not palette_ready:
                        mode = args.palette_file.read_text().strip()
                        if mode not in ("light", "dark"):
                            raise ValueError("Waiting for a valid palette")
                        palette_ready = True
                    result = subprocess.run(
                        [args.niri, "msg", "--json", "outputs"], check=True,
                        capture_output=True, text=True, timeout=3,
                    )
                    desired = desired_outputs(json.loads(result.stdout), locked=swaylock_running())
                    last_error = None
                except (OSError, ValueError, subprocess.SubprocessError) as error:
                    # Invalidate stale topology, e.g. on compositor reconnect.
                    desired = {}
                    message = str(error)
                    if message != last_error:
                        log(f"Waiting for desktop state: {message}")
                    last_error = message
                if stopping.is_set():
                    break
                supervisor.reconcile(desired)
                stopping.wait(1)
        finally:
            supervisor.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f"cloudscape: {error}", file=sys.stderr)
        sys.exit(1)
