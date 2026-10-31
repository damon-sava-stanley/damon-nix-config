import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = Path(os.environ.get('NOTE_BRIDGE_SCRIPT', ROOT / 'home/damon/bin/note-checkpoint-bridge.py'))
CHECKPOINT = Path(os.environ.get('NOTE_CHECKPOINT_SCRIPT', ROOT / 'home/damon/bin/note-checkpoint.py'))

class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.notes = self.root / 'notes'
        self.notes.mkdir()
        (self.notes / '.gitignore').write_text('')
        (self.notes / 'note.md').write_text('recover me')
        self.socket = self.root / 'control.sock'
        self.state = self.root / 'state'

    def start(self, uid=None):
        process = subprocess.Popen([sys.executable, str(BRIDGE), '--socket', str(self.socket),
            '--allowed-uid', str(os.getuid() if uid is None else uid), '--notes', str(self.notes),
            '--state', str(self.state), '--remote', str(self.root / 'missing.git'),
            '--checkpoint', str(CHECKPOINT)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        def stop():
            process.terminate()
            try: process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
        self.addCleanup(stop)
        for _ in range(100):
            if self.socket.exists(): return
            if process.poll() is not None: self.fail(process.stderr.read().decode())
            time.sleep(.02)
        self.fail('bridge did not start')

    def request(self, data):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.settimeout(5)
            peer.connect(str(self.socket))
            try:
                peer.sendall(data)
                response = b''
                while b'\n' not in response:
                    chunk = peer.recv(4096)
                    if not chunk: break
                    response += chunk
                return json.loads(response) if response else None
            except (ConnectionResetError, BrokenPipeError):
                return None

    def test_real_local_checkpoint_without_network(self):
        self.start()
        receipt = self.request(b'{"version":1,"op":"checkpoint"}\n')
        self.assertTrue(receipt['ok'])
        self.assertEqual(receipt['root'], str(self.notes))
        self.assertRegex(receipt['commit'], r'^[a-f0-9]{40}$')
        self.assertEqual(self.socket.stat().st_mode & 0o777, 0o660)
        self.assertNotIn('last_push', json.loads((self.state / 'status.json').read_text()))

    def test_untrusted_inputs_do_not_execute(self):
        self.start()
        for data in [b'{}\n', b'{"version":true,"op":"checkpoint"}\n',
                     b'{"version":1,"op":"checkpoint","command":"evil"}\n',
                     b'{"version":1,"op":"status"}\n', b'x' * 1100 + b'\n']:
            response = self.request(data)
            self.assertFalse(response and response.get('ok'))
        self.assertFalse(self.state.exists())

    def test_wrong_peer_uid_cannot_checkpoint(self):
        self.start(os.getuid() + 1)
        response = self.request(b'{"version":1,"op":"checkpoint"}\n')
        self.assertFalse(response and response.get('ok'))
        self.assertFalse(self.state.exists())

    def test_checkpoint_failure_is_generic(self):
        (self.notes / '.gitignore').unlink()
        self.start()
        response = self.request(b'{"version":1,"op":"checkpoint"}\n')
        self.assertEqual(response, {'version': 1, 'ok': False, 'error': 'Local checkpoint failed'})

if __name__ == '__main__': unittest.main()
