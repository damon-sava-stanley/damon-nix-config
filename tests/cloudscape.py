#!/usr/bin/env python3
"""Lifecycle tests without changing the real compositor, outputs, or lock."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cloudscape", ROOT / "home/damon/cloudscape/supervisor.py")
cloudscape = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = cloudscape
spec.loader.exec_module(cloudscape)


def output(width=1920, height=1080, enabled=True):
    return {"current_mode": 0, "logical": {
        "width": width, "height": height, "scale": 1, "transform": "Normal",
    } if enabled else None}


class Process:
    returncode = None

    def poll(self):
        return self.returncode


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.started = []
        self.stopped = []

        def spawn(name, signature):
            process = Process()
            self.started.append((name, signature, process))
            return process

        def stop(process):
            self.stopped.append(process)
            process.returncode = 0

        self.supervisor = cloudscape.Supervisor(spawn, stop, lambda: self.now)
        self.outputs = {"DP-7": output(), "DP-8": output()}

    def reconcile(self, locked=False, off=()):
        desired = cloudscape.desired_outputs(self.outputs, locked=locked,
                                             is_powered=lambda name: name not in off)
        self.supervisor.reconcile(desired)

    def test_startup_and_unchanged_outputs(self):
        self.reconcile()
        self.reconcile()
        self.assertEqual(len(self.started), 2)
        self.assertEqual(self.started[0][1][:2], (533, 300))

    def test_startup_locked_or_powered_off(self):
        self.reconcile(locked=True)
        self.reconcile(off=("DP-7", "DP-8"))
        self.assertFalse(self.started)

    def test_unlock_does_not_resume_powered_off_output(self):
        self.reconcile()
        self.reconcile(locked=True)
        self.assertEqual(len(self.stopped), 2)
        self.reconcile(off=("DP-7", "DP-8"))
        self.assertEqual(len(self.started), 2)
        self.reconcile(off=("DP-8",))
        self.assertEqual(set(self.supervisor.children), {"DP-7"})

    def test_wake_does_not_resume_while_locked(self):
        self.reconcile(off=("DP-7", "DP-8"), locked=True)
        self.reconcile(locked=True)
        self.assertFalse(self.started)
        self.reconcile()
        self.assertEqual(len(self.started), 2)

    def test_disable_replug_and_resize_leave_other_output_running(self):
        self.reconcile()
        original = self.supervisor.children["DP-8"].process
        self.outputs["DP-7"] = output(enabled=False)
        self.reconcile()
        self.assertEqual(set(self.supervisor.children), {"DP-8"})
        self.outputs["DP-7"] = output(2880, 1920)
        self.reconcile()
        self.assertEqual(self.supervisor.children["DP-7"].signature[:2], (450, 300))
        self.outputs["DP-7"] = output(1080, 1920)
        self.reconcile()
        self.assertEqual(self.supervisor.children["DP-7"].signature[:2], (169, 300))
        self.assertIs(self.supervisor.children["DP-8"].process, original)

    def test_zero_outputs_and_reconnect(self):
        self.reconcile()
        self.outputs = {}
        self.reconcile()
        self.assertFalse(self.supervisor.children)
        self.outputs = {"DP-7": output()}
        self.reconcile()
        self.assertEqual(set(self.supervisor.children), {"DP-7"})

    def test_unplug_while_locked(self):
        self.reconcile()
        self.reconcile(locked=True)
        del self.outputs["DP-7"]
        self.reconcile(locked=True)
        self.reconcile()
        self.assertEqual(set(self.supervisor.children), {"DP-8"})

    def test_failure_is_isolated_and_backed_off(self):
        self.reconcile()
        other = self.supervisor.children["DP-8"].process
        self.supervisor.children["DP-7"].process.returncode = 1
        self.reconcile()
        self.assertEqual(self.supervisor.retry_at["DP-7"], 1)
        self.reconcile()
        self.assertEqual(len(self.started), 2)
        self.now = 1
        self.reconcile()
        self.supervisor.children["DP-7"].process.returncode = 1
        self.reconcile()
        self.assertEqual(self.supervisor.retry_at["DP-7"], 3)
        self.assertIs(self.supervisor.children["DP-8"].process, other)

    def test_long_success_resets_failure_backoff(self):
        self.reconcile()
        self.supervisor.failures["DP-7"] = 5
        self.now = 61
        self.supervisor.children["DP-7"].process.returncode = 1
        self.reconcile()
        self.assertEqual(self.supervisor.retry_at["DP-7"], 62)

    def test_spawn_failure_and_cleanup(self):
        def fail(*_):
            raise OSError("cannot start")
        self.supervisor.spawn = fail
        self.reconcile()
        self.assertFalse(self.supervisor.children)
        self.assertEqual(self.supervisor.failures, {"DP-7": 1, "DP-8": 1})
        self.supervisor.close()
        self.assertFalse(self.supervisor.failures)


class SensorTests(unittest.TestCase):
    def test_dpms_and_duplicate_connectors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            connector = root / "card1-DP-7"
            connector.mkdir()
            (connector / "dpms").write_text("Off\n")
            self.assertFalse(cloudscape.powered("DP-7", root))
            self.assertTrue(cloudscape.powered("DP-8", root))
            (connector / "dpms").write_text("On\n")
            self.assertTrue(cloudscape.powered("DP-7", root))
            other = root / "card2-DP-7"
            other.mkdir()
            (other / "dpms").write_text("Off\n")
            self.assertTrue(cloudscape.powered("DP-7", root))

    def test_swaylock_detection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            process = root / "123"
            process.mkdir()
            (process / "comm").write_text("swaylock\n")
            self.assertTrue(cloudscape.swaylock_running(root))
            self.assertFalse(cloudscape.swaylock_running(root, uid=os.getuid() + 1))
            (process / "comm").write_text("other\n")
            self.assertFalse(cloudscape.swaylock_running(root))
            (process / "comm").unlink()
            self.assertFalse(cloudscape.swaylock_running(root))


if __name__ == "__main__":
    unittest.main()
