import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_host_update', Path(__file__).parents[1] / 'scripts/check-host-update.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class HostUpdateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.old = Path(self.directory.name) / 'old'
        self.new = Path(self.directory.name) / 'new'

    def write(self, root, relative, value):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))
        return path

    def generation(self, root, epoch='epoch', bundle='bundle', retired=None):
        self.write(root, 'etc/remote-zettel-work-generation.json', dict(epoch=epoch, bundle=bundle, retired=retired or {}))

    def test_application_only_update_is_allowed(self):
        self.generation(self.old)
        self.generation(self.new)
        self.assertEqual(checker.check(self.old, self.new), [])

    def test_same_epoch_toolchain_change_is_refused(self):
        self.generation(self.old)
        self.generation(self.new, bundle='new-toolchain')
        self.assertIn('explicit Work policy migration', checker.check(self.old, self.new)[0])

    def test_explicit_new_epoch_is_left_to_privileged_transition_checks(self):
        self.generation(self.old)
        self.generation(self.new, epoch='new-epoch', bundle='new-toolchain', retired={'epoch': 'bundle'})
        self.assertEqual(checker.check(self.old, self.new), [])

    def test_retired_epoch_cannot_be_selected_by_ordinary_install(self):
        self.generation(self.old, epoch='current', retired={'old': 'old-bundle'})
        self.generation(self.new, epoch='old', bundle='old-bundle')
        self.assertIn('not a declared successor', checker.check(self.old, self.new)[0])

    def test_new_software_transition_uses_its_operator(self):
        self.write(self.new, 'etc/remote-zettel-host-software-transition.json', {'epoch': 'next'})
        self.assertIn('prepared host migration operator', checker.check(self.old, self.new)[0])
        self.write(self.old, 'etc/remote-zettel-host-software-transition.json', {'epoch': 'next'})
        self.assertEqual(checker.check(self.old, self.new), [])

    def test_removing_enrolled_work_contract_is_refused(self):
        self.generation(self.old)
        self.assertIn('removes', checker.check(self.old, self.new)[0])

    def test_fresh_install_has_no_previous_policy(self):
        self.generation(self.new)
        self.assertEqual(checker.check(self.old, self.new), [])

    def test_controller_policy_is_compared_by_contents(self):
        for root in [self.old, self.new]:
            config = self.write(root, 'controller.json', dict(adapterCommand='old-adapter'))
            self.write(root, 'etc/remote-zettel-self-deployment/bridge.json', dict(
                controllerStateDirectory='/var/lib/controller', controllerConfigurationFile=str(config)))
        self.assertEqual(checker.check(self.old, self.new), [])
        self.write(self.new, 'controller.json', dict(adapterCommand='new-adapter'))
        self.assertIn('journal policy migration is not implemented', checker.check(self.old, self.new)[0])

    def test_malformed_metadata_fails_instead_of_allowing_switch(self):
        self.write(self.old, 'etc/remote-zettel-work-generation.json', {})
        self.generation(self.new)
        with self.assertRaises(KeyError):
            checker.check(self.old, self.new)


class InstallerTests(unittest.TestCase):
    def run_installer(self, *args, preflight=0, build=0):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / 'target system'
            target.mkdir()
            log = root / 'calls'
            mocks = root / 'bin'
            mocks.mkdir()
            commands = {
                'nix': '''#!/usr/bin/env bash
echo build >> "$CALL_LOG"
if [[ $BUILD_RESULT != 0 ]]; then exit "$BUILD_RESULT"; fi
while [[ $# -gt 0 ]]; do
  if [[ $1 == --out-link ]]; then ln -s "$BUILT_TARGET" "$2"; break; fi
  shift
done
''',
                'python3': '#!/usr/bin/env bash\necho preflight >> "$CALL_LOG"\nexit "$PREFLIGHT_RESULT"\n',
                'sudo': '#!/usr/bin/env bash\nprintf "%s\\n" "$@" >> "$CALL_LOG"\n',
            }
            for name, script in commands.items():
                path = mocks / name
                path.write_text(script)
                path.chmod(0o755)
            result = subprocess.run(['bash', str(Path(__file__).parents[1] / 'install.sh'), *args],
                env=dict(os.environ, PATH=str(mocks) + ':' + os.environ['PATH'],
                         CALL_LOG=str(log), BUILT_TARGET=str(target),
                         PREFLIGHT_RESULT=str(preflight), BUILD_RESULT=str(build)),
                capture_output=True, text=True)
            return result.returncode, log.read_text().splitlines() if log.exists() else [], str(target)

    def test_failed_build_never_reaches_preflight_or_sudo(self):
        code, calls, _ = self.run_installer(build=1)
        self.assertEqual(code, 1)
        self.assertEqual(calls, ['build'])

    def test_policy_conflict_never_reaches_sudo(self):
        code, calls, _ = self.run_installer(preflight=1)
        self.assertEqual(code, 1)
        self.assertEqual(calls, ['build', 'preflight'])

    def test_check_mode_never_reaches_sudo(self):
        code, calls, _ = self.run_installer('--check')
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['build', 'preflight'])

    def test_switch_uses_exact_checked_store_path(self):
        code, calls, target = self.run_installer()
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['build', 'preflight', 'nixos-rebuild', 'switch', '--store-path', target])


if __name__ == '__main__':
    unittest.main()
