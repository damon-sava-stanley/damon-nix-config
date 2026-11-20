import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resume = load('resume', Path(__file__).parents[1] / 'scripts/resume-host-deployment.py')
host = load('host', os.environ['RESUME_PREVIOUS_SCRIPTS'] + '/work-host-policy-upgrade.py')
u = host.upgrade



class Readiness(unittest.TestCase):
    def setUp(self):
        self.now = 0
        patcher = patch.object(resume.time, 'monotonic', side_effect=lambda: self.now)
        patcher.start(); self.addCleanup(patcher.stop)
        def advance(seconds):
            self.now += seconds
        patcher = patch.object(resume.time, 'sleep', side_effect=advance)
        patcher.start(); self.addCleanup(patcher.stop)

    def test_active_service_can_have_a_delayed_work_socket(self):
        from unittest.mock import Mock
        board = {'repositories': ['owner/stories', 'owner/software']}
        probe = Mock(side_effect=[FileNotFoundError('socket not yet created'),
            subprocess.CalledProcessError(1, ['work', 'board']), json.dumps(board)])
        self.assertEqual(resume.wait_for_work_board(probe, board['repositories']), board)
        self.assertEqual(probe.call_count, 3)
        self.assertGreater(self.now, 0)
        self.assertTrue(all(0 < call.args[0] <= 5 for call in probe.call_args_list))

    def test_failed_readiness_has_a_deadline(self):
        from unittest.mock import Mock
        probe = Mock(side_effect=subprocess.CalledProcessError(1, ['work', 'board']))
        with self.assertRaisesRegex(ValueError, 'deadline; recovery hold retained'):
            resume.wait_for_work_board(probe, ['owner/software'], timeout=1)
        self.assertEqual(self.now, 1)
        self.assertEqual(probe.call_count, 2)

    def test_foreign_repository_is_not_treated_as_ready(self):
        from unittest.mock import Mock
        probe = Mock(return_value=json.dumps({'repositories': ['other/repository']}))
        with self.assertRaisesRegex(ValueError, 'Unexpected Work repository'):
            resume.wait_for_work_board(probe, ['owner/software'])
        self.assertEqual(probe.call_count, 1)

    def test_readiness_does_not_depend_on_the_operator_working_directory(self):
        import sys
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as temporary:
            os.chdir(temporary)
            os.rmdir(temporary)
            try:
                self.assertEqual(resume.read_board_command([sys.executable, '-c', 'print("ready")'], os.environ, 1), b'ready\n')
            finally:
                os.chdir(previous)

    def test_a_hung_read_is_terminated(self):
        import sys
        with self.assertRaises(subprocess.TimeoutExpired):
            resume.read_board_command([sys.executable, '-c', 'import time; time.sleep(20)'], os.environ, 0.05)


@unittest.skipUnless(os.geteuid() == 0, 'protected filesystem integration requires disposable root VM')
class Journals(unittest.TestCase):
    def setUp(self):
        os.umask(0o077)
        self.root = Path(tempfile.mkdtemp(prefix='deployment-resume-test-', dir='/var/lib'))
        self.addCleanup(shutil.rmtree, self.root)
        self.state = self.root / 'receipts'
        u.mkdir(self.state)
        os.environ['RESUME_BRIDGE'] = str(Path(os.environ['RESUME_BRIDGE']).resolve(strict=True))
        self.bridge = json.loads(Path(os.environ['RESUME_BRIDGE']).read_text())
        self.bridge.update(controllerStateDirectory=str(self.root / 'controller'), deliveryStatePath=str(self.root / 'delivery/delivery.sqlite'))

    def initialize(self, stage):
        configuration = json.loads(Path(self.bridge['controllerConfigurationFile']).read_text())
        for key in ('adapterCommand', 'verifierCommand'):
            configuration[key] = os.path.realpath(configuration[key])
        controller = load('controller', self.bridge['controllerScript']).Controller(stage / 'controller', configuration,
            runner=lambda *_: self.fail('Commissioning must not invoke an adapter'))
        controller.close()
        subprocess.run([os.environ['RESUME_NODE'], os.environ['RESUME_HELPER'], os.environ['RESUME_APPLICATION'],
            os.environ['RESUME_BRIDGE'], 'initialize', str(stage / 'delivery/delivery.sqlite')],
            check=True, stdout=subprocess.DEVNULL)

    def install(self, initialize=None):
        resume.install_journals(u, self.state, self.bridge, initialize or self.initialize)

    def test_real_policy_bound_journals_and_replay(self):
        self.install()
        resume.empty_journals(host, self.bridge)
        first = resume.inventory(self.root / 'controller')
        self.install(lambda _: self.fail('Replay must not initialize again'))
        self.assertEqual(first, resume.inventory(self.root / 'controller'))

    def test_interrupted_second_rename_preserves_first_journal(self):
        original = os.rename
        def interrupt(source, destination):
            if Path(destination) == self.root / 'delivery':
                raise OSError('interrupted rename')
            original(source, destination)
        with patch.object(resume.os, 'rename', side_effect=interrupt):
            with self.assertRaisesRegex(OSError, 'interrupted rename'):
                self.install()
        inode = (self.root / 'controller/state.sqlite').stat().st_ino
        self.install(lambda _: self.fail('Sealed journals must be reused'))
        self.assertEqual(inode, (self.root / 'controller/state.sqlite').stat().st_ino)
        resume.empty_journals(host, self.bridge)

    def test_unsealed_partial_stage_does_not_install_or_reset(self):
        partial = []
        def interrupt(stage):
            (stage / 'controller/partial').write_text('uncommitted private stage')
            partial.append(stage)
            raise OSError('commissioning interrupted')
        with self.assertRaisesRegex(OSError, 'commissioning interrupted'):
            self.install(interrupt)
        self.assertFalse((self.root / 'controller').exists())
        self.install()
        self.assertEqual((partial[0] / 'controller/partial').read_text(), 'uncommitted private stage')

    def test_foreign_namespace_is_never_adopted(self):
        (self.root / 'controller').mkdir(mode=0o700)
        with self.assertRaisesRegex(ValueError, 'without its sealed'):
            self.install(lambda _: self.fail('Foreign journal must refuse before commissioning'))

    def test_changed_installed_journal_is_never_replaced(self):
        self.install()
        file = self.root / 'controller/state.sqlite'
        with file.open('ab') as stream:
            stream.write(b'changed')
        with self.assertRaisesRegex(ValueError, 'differs from its sealed'):
            self.install()
        self.assertTrue(file.read_bytes().endswith(b'changed'))


if __name__ == '__main__':
    unittest.main()
