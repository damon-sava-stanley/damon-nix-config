import importlib.util
import pathlib
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('policy', pathlib.Path(__file__).resolve().parents[1] / 'scripts/power-policy.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PolicyTests(unittest.TestCase):
    def test_power_detection(self):
        for code, expected in [(0, True), (1, False), (2, None), (255, None)]:
            with self.subTest(code=code), patch.object(policy.subprocess, 'run') as run:
                run.return_value.returncode = code
                self.assertIs(policy.on_ac(), expected)
                run.assert_called_once_with(['systemd-ac-power'], check=False)

    def test_idle_wait_rechecks_ac_until_unplugged(self):
        with patch.object(policy, 'on_ac', side_effect=[True, None, True, False]), \
             patch.object(policy.time, 'sleep') as delay, \
             patch.object(policy.subprocess, 'run') as run:
            policy.wait_for_battery()
        self.assertEqual(delay.call_count, 3)
        run.assert_called_once_with(['systemctl', 'suspend-then-hibernate'], check=True)

    def test_already_on_battery(self):
        with patch.object(policy, 'on_ac', return_value=False), \
             patch.object(policy.time, 'sleep') as delay, \
             patch.object(policy.subprocess, 'run') as run:
            policy.wait_for_battery()
        delay.assert_not_called()
        run.assert_called_once_with(['systemctl', 'suspend-then-hibernate'], check=True)

    def test_cancel_while_waiting_never_sleeps(self):
        with patch.object(policy, 'on_ac', return_value=True), \
             patch.object(policy.time, 'sleep', side_effect=KeyboardInterrupt), \
             patch.object(policy.subprocess, 'run') as run:
            with self.assertRaises(KeyboardInterrupt):
                policy.wait_for_battery()
        run.assert_not_called()

    def test_sleep_failure_is_reported(self):
        with patch.object(policy, 'on_ac', return_value=False), \
             patch.object(policy.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'systemctl')):
            with self.assertRaises(subprocess.CalledProcessError):
                policy.wait_for_battery()


unittest.main()
