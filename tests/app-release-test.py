import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

root = Path(__file__).parents[1]
operator = load('release_test', root / 'scripts/start-app-release-test.py')
host = load('host', '/nix/store/f92c9dbzqfgkcc8v7gwvr0w252p8szc9-work-host-policy-upgrade-scripts/work-host-policy-upgrade.py')

class Freshness(unittest.TestCase):
    def test_policy_only_is_fresh_but_any_task_or_deployment_history_refuses(self):
        import contextlib
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript('CREATE TABLE policy(value TEXT); INSERT INTO policy VALUES("bound"); CREATE TABLE work_runs(id TEXT); CREATE TABLE deployments(id TEXT);')
        @contextlib.contextmanager
        def database(_):
            yield db
        with patch.object(host.upgrade, 'database', side_effect=database):
            operator.fresh_databases(host.upgrade, [Path('/unused')])
            for table in ('work_runs', 'deployments'):
                db.execute('INSERT INTO '+table+' VALUES("history")')
                with self.assertRaisesRegex(ValueError, 'before-first-task'):
                    operator.fresh_databases(host.upgrade, [Path('/unused')])
                db.execute('DELETE FROM '+table)

class TaskDocument(unittest.TestCase):
    @unittest.skipIf(os.geteuid() == 0, 'exercise the document writer without root privilege')
    def test_create_only_document_replay_preserves_user_edits(self):
        import hashlib
        import sys
        import uuid
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); documents = base / 'documents'; (documents / 'tasks').mkdir(parents=True)
            document = base / 'task.md'; document.write_text('reviewed task\n')
            task_id = str(uuid.uuid4())
            plan = {'webUid': os.geteuid(), 'documentsRoot': str(documents), 'taskId': task_id,
                'taskDocument': str(document), 'taskRevision': hashlib.sha256(document.read_bytes()).hexdigest()}
            manifest = base / 'plan.json'; manifest.write_text(json.dumps(plan))
            command = [sys.executable, '-I', str(root / 'scripts/release-test-task.py'), str(manifest)]
            subprocess.run(command, check=True)
            target = documents / 'tasks' / (task_id + '.md'); inode = target.stat().st_ino
            subprocess.run(command, check=True)
            self.assertEqual(target.stat().st_ino, inode)
            target.write_text('user edited the task')
            self.assertNotEqual(subprocess.run(command, stderr=subprocess.DEVNULL).returncode, 0)
            self.assertEqual(target.read_text(), 'user edited the task')

@unittest.skipUnless(os.geteuid() == 0, 'root-only protected-source fixture')
class ProtectedSource(unittest.TestCase):
    def test_exact_fast_forward_preserves_source_policy_and_replays(self):
        import hashlib
        import shutil
        fixture = Path(os.environ['RELEASE_FIXTURE'])
        base = Path(tempfile.mkdtemp(prefix='release-source-test-', dir='/var/lib'))
        self.addCleanup(shutil.rmtree, base)
        source, state, receipts = base / 'source', base / 'state', base / 'receipts'
        shutil.copytree(fixture / 'source', source)
        source.chmod(0o700)
        state.mkdir(mode=0o755); receipts.mkdir(mode=0o700)
        configuration = {'repository': str(source), 'stateDirectory': str(state)}
        manifest = json.loads((fixture / 'manifest.json').read_text())
        application = os.environ['RELEASE_APPLICATION']
        node = os.environ['RELEASE_NODE']
        program = "import {commissionProtectedPublicationSource,ProtectedPublicationSource} from '"+application+"/src/work/publication-source-advance.js'; import {canonicalPromotionJson} from '"+application+"/src/work/publisher-candidate-input.js'; import {createHash} from 'node:crypto'; const c="+json.dumps(configuration)+"; if(process.argv[1]==='initialize') commissionProtectedPublicationSource(c,'"+manifest['oldBase']+"'); const owner=new ProtectedPublicationSource(c); try { process.stdout.write(createHash('sha256').update(canonicalPromotionJson(owner.policy())).digest('hex')); } finally {owner.close();}"
        before = subprocess.check_output([node, '--input-type=module', '-e', program, 'initialize'])
        bootstrap = load('bootstrap', root / 'scripts/remote-zettel-publication-bootstrap.py')
        bootstrap.advance_bootstrap(host.upgrade.install, receipts, configuration, fixture / 'pack', manifest)
        after = subprocess.check_output([node, '--input-type=module', '-e', program, 'verify'])
        self.assertEqual(before, after)
        self.assertEqual((state / 'base').read_text(), manifest['newBase']+'\n')
        self.assertEqual((source / '.git/refs/heads/publication-base').read_text(), manifest['newBase']+'\n')
        bootstrap.advance_bootstrap(host.upgrade.install, receipts, configuration, fixture / 'pack', manifest)
        self.assertEqual(before, subprocess.check_output([node, '--input-type=module', '-e', program, 'verify']))

    def test_existing_software_task_prevents_bootstrap(self):
        import shutil
        base = Path(tempfile.mkdtemp(prefix='release-task-test-', dir='/var/lib'))
        self.addCleanup(shutil.rmtree, base)
        documents = base / 'documents'; (documents / 'tasks').mkdir(parents=True)
        (documents / 'tasks/task.md').write_text('existing task')
        bootstrap = load('bootstrap_fresh', root / 'scripts/remote-zettel-publication-bootstrap.py')
        with self.assertRaisesRegex(ValueError, 'task documents already exist'):
            bootstrap.empty_coordinator(base / 'state.sqlite', 0, str(documents))

if __name__ == '__main__':
    unittest.main()
