import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/note-checkpoint.py'
IGNORE = '*\n!*/\n!*.md\n!*.bib\n!sources.json\n!.gitignore\n'

class CheckpointTest(unittest.TestCase):
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
