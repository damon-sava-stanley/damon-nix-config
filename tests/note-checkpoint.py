import os
import fcntl
import time
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(os.environ.get('NOTE_CHECKPOINT_SCRIPT', Path(__file__).resolve().parents[1] / 'home/damon/bin/note-checkpoint.py'))

class CheckpointTest(unittest.TestCase):
    def test_local_checkpoint_waits_for_existing_timer_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            notes, state = root / 'notes', root / 'state'
            notes.mkdir()
            state.mkdir()
            (notes / '.gitignore').write_text('')
            with (state / 'lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                child = subprocess.Popen(['python3', str(SCRIPT), '--notes', str(notes), '--state', str(state), '--remote', str(root / 'missing.git'), '--local-only'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    time.sleep(.2)
                    self.assertIsNone(child.poll())
                    self.assertFalse((state / 'status.json').exists())
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    _, errors = child.communicate(timeout=5)
                    self.assertEqual(child.returncode, 0, errors.decode())
                finally:
                    if child.poll() is None:
                        child.kill()
                        child.communicate()

    def test_local_checkpoint_does_not_require_remote(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            notes = root / 'notes'
            notes.mkdir()
            (notes / '.gitignore').write_text('')
            (notes / 'note.md').write_text('recover me')
            command = ['python3', str(SCRIPT), '--notes', str(notes), '--state', str(root / 'state'), '--remote', str(root / 'missing.git'), '--local-only']
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            import json
            receipt = json.loads(result.stdout)
            self.assertEqual(receipt['root'], str(notes))
            self.assertRegex(receipt['commit'], r'^[a-f0-9]{40}$')
            status = json.loads((root / 'state/status.json').read_text())
            self.assertNotIn('last_push', status)

    def test_history_and_push_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            notes = root / 'notes'
            notes.mkdir()
            # A permissive ignore file must not defeat the script's allowlist.
            (notes / '.gitignore').write_text('')
            (notes / '*.md').write_text('literal wildcard filename')
            (notes / '.hidden').mkdir()
            (notes / '.hidden/private.md').write_text('must not upload')
            (notes / 'note.md').write_text('first')
            (notes / 'attachment.pdf').write_text('excluded')
            remote = root / 'remote.git'
            subprocess.run(['git', 'init', '--bare', str(remote)], check=True, capture_output=True)
            state = root / 'state'
            env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.com', GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.com')
            command = ['python3', str(SCRIPT), '--notes', str(notes), '--state', str(state), '--remote', str(remote)]
            def run(ok=True):
                result = subprocess.run(command, env=env, capture_output=True)
                self.assertEqual(result.returncode == 0, ok, result.stderr.decode())
            def git(*args):
                return subprocess.check_output(['git', '--git-dir', str(state / 'history.git'), *args], text=True).strip()
            run()
            self.assertEqual(git('ls-tree', '-r', '--name-only', 'HEAD'), '*.md\n.gitignore\nnote.md')
            self.assertFalse((notes / '.git').exists())
            first = git('rev-parse', 'HEAD')
            run()
            self.assertEqual(first, git('rev-parse', 'HEAD'))
            (notes / 'note.md').write_text('second')
            remote.rename(root / 'offline.git')
            run(False)
            self.assertNotEqual(first, git('rev-parse', 'HEAD'))
            (root / 'offline.git').rename(remote)
            run()
            (notes / 'note.md').unlink()
            run()
            self.assertEqual(git('ls-tree', '-r', '--name-only', 'HEAD'), '*.md\n.gitignore')
            self.assertEqual(git('rev-list', '--count', 'HEAD'), '3')
            self.assertEqual(git('rev-parse', 'HEAD'), subprocess.check_output(['git', '--git-dir', str(remote), 'rev-parse', 'refs/heads/main'], text=True).strip())

if __name__ == '__main__':
    unittest.main()
