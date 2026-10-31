#!/usr/bin/env python3
import importlib.util
import io
import json
import os
import pathlib
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'scripts/work-backup.py'
spec = importlib.util.spec_from_file_location('work_backup', SOURCE)
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class BackupTests(unittest.TestCase):
    def fixture(self, root, drain=(True, True, True), failure=None, inactive=False):
        calls = []
        answers = iter(drain)
        active = {'web', 'host', 'supervisor'} if not inactive else {'web'}
        class Fake(backup.Backup):
            def active(self, unit): return unit in active
            def drained(self): return next(answers)
            def control(self, action, units):
                calls.append((action, units))
                if action == 'stop': active.difference_update(units)
                else: active.update(units)
            def capture(self):
                calls.append(('capture', []))
                if failure == 'capture': raise RuntimeError('capture')
                return pathlib.Path(root) / 'stage'
            def validate_and_publish(self, stage):
                self.assert_restored = active == {'web', 'host', 'supervisor'}
                if failure == 'publish': raise RuntimeError('publish')
                return 'fixture'
        return Fake({'backupRoot': root, 'units': ['supervisor', 'host', 'web'], 'webUnit': 'web'}), calls

    def test_busy_skips_without_stopping_or_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            b, calls = self.fixture(temp, drain=(False,))
            self.assertEqual(b.run(), 'skipped-busy')
            self.assertEqual(calls, [])
            self.assertFalse(b.recovery.exists())

    def test_inactive_services_not_started(self):
        with tempfile.TemporaryDirectory() as temp:
            b, calls = self.fixture(temp, inactive=True)
            self.assertEqual(b.run(), 'skipped-services-inactive')
            self.assertEqual(calls, [])

    def test_race_restores_only_web(self):
        with tempfile.TemporaryDirectory() as temp:
            b, calls = self.fixture(temp, drain=(True, False))
            self.assertEqual(b.run(), 'skipped-admission-race')
            self.assertEqual(calls, [('stop', ['web']), ('start', ['web'])])
            self.assertFalse(b.recovery.exists())

    def test_capture_failure_recovers_all_services(self):
        with tempfile.TemporaryDirectory() as temp:
            b, calls = self.fixture(temp, failure='capture')
            with self.assertRaises(RuntimeError): b.run()
            self.assertEqual(calls[-1], ('start', ['supervisor', 'host', 'web']))
            self.assertFalse(b.recovery.exists())

    def test_success_and_publish_failure_resume_before_verify(self):
        for failure in (None, 'publish'):
            with tempfile.TemporaryDirectory() as temp:
                b, calls = self.fixture(temp, failure=failure)
                if failure:
                    with self.assertRaises(RuntimeError): b.run()
                else: self.assertEqual(b.run(), 'completed:fixture')
                self.assertTrue(b.assert_restored)
                self.assertFalse(b.recovery.exists())

    def test_recovery_marker_survives_failed_restart(self):
        with tempfile.TemporaryDirectory() as temp:
            b, _ = self.fixture(temp)
            backup.atomic_json(b.recovery, ['web'])
            with patch.object(b, 'control', side_effect=RuntimeError('systemctl')):
                with self.assertRaises(RuntimeError): b.recover()
            self.assertTrue(b.recovery.exists())
            b.recover()
            self.assertFalse(b.recovery.exists())

    def test_real_archive_excludes_credentials_and_preserves_link_and_acl(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            config = {'backupRoot': str(root / 'backup'), 'units': []}
            pathlib.Path(config['backupRoot']).mkdir()
            for key in ['documents', 'coordinator', 'host', 'executor', 'source', 'scratch']:
                path = root / key; path.mkdir(); config[key] = str(path)
            (root / 'executor/operations').mkdir()
            b = backup.Backup(config)
            for path, _ in b.checks():
                db = sqlite3.connect(path); db.execute('CREATE TABLE fixture (id INTEGER)'); db.close()
            for suffix in ['', '-wal', '-shm', '.ownership.sqlite']:
                (root / 'host' / ('credentials.sqlite' + suffix)).write_text('SYNTHETIC SECRET')
            (root / 'executor/alias').symlink_to('/must/not/be/followed')
            task = root / 'documents/task.md'; task.write_text('fixture')
            acl_result = subprocess.run(['setfacl', '-m', 'u:65534:r--', str(task)], capture_output=True, text=True)
            if acl_result.returncode and 'Operation not supported' not in acl_result.stderr:
                self.fail(acl_result.stderr)
            stage = b.capture()
            archive = stage / 'work.tar'
            result = backup.verify(archive, [str(p).lstrip('/') for p, _ in b.checks()])
            self.assertEqual(result['sqliteDatabases'], 4)
            self.assertEqual(result['retainedLinksNotFollowed'], 1)
            with tarfile.open(archive) as tar:
                self.assertFalse(any('credentials.sqlite' in m.name for m in tar))
                if acl_result.returncode == 0:
                    acl = tar.getmember(str(task).lstrip('/')).pax_headers['SCHILY.acl.access']
                    self.assertIn(':65534', acl)
                # The Nix build sandbox may lack ACLs; the VM asserts this unconditionally.

    def test_capture_timeout_kills_child_before_return(self):
        with tempfile.TemporaryDirectory() as temp:
            marker = pathlib.Path(temp) / 'late'
            with self.assertRaises(subprocess.TimeoutExpired):
                backup.capture_command(['sh', '-c', f'(sleep 0.4; touch {marker}) & wait'], 0.1)
            import time
            time.sleep(0.5)
            self.assertFalse(marker.exists())

    def test_unsafe_destination_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp); dest = root / 'public'; dest.mkdir(mode=0o755)
            with self.assertRaises(ValueError): backup.publish(dest, {'name': 'snapshot-test', 'files': []})
            link = root / 'link'; link.symlink_to(dest)
            with self.assertRaises(ValueError): backup.publish(link, {'name': 'snapshot-test', 'files': []})

    def test_wal_integrity_uses_sidecar(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp); path = root / 'state.sqlite'
            db = sqlite3.connect(path)
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('CREATE TABLE fixture (id INTEGER)'); db.commit()
            db.execute('INSERT INTO fixture VALUES (1)'); db.commit()
            archive = root / 'work.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for source in root.glob('state.sqlite*'): tar.add(source, arcname='state/' + source.name)
            result = backup.verify(archive, ['state/state.sqlite'])
            self.assertEqual(result['sqliteDatabases'], 1)
            db.close()

    def test_corruption_credentials_and_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = pathlib.Path(temp) / 'work.tar.gz'
            for name, content, dbs in [('host/credentials.sqlite-wal', b'secret', []),
                                       ('../escape', b'', []),
                                       ('host/admission.sqlite', b'not sqlite', ['host/admission.sqlite'])]:
                with tarfile.open(archive, 'w:gz') as tar:
                    m = tarfile.TarInfo(name); m.size = len(content); tar.addfile(m, io.BytesIO(content))
                with self.assertRaises((ValueError, sqlite3.DatabaseError)):
                    backup.verify(archive, dbs)

    def test_publish_checksums_no_overwrite_and_failed_copy_not_completed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp); dest = root / 'dropbox'; dest.mkdir(mode=0o700)
            source = root / 'payload'; source.write_text('fixture')
            def entries(checksum):
                return {'name': 'snapshot-fixture', 'files': [{'name': 'work.tar.gz',
                         'fd': os.open(source, os.O_RDONLY), 'sha256': checksum}]}
            backup.publish(dest, entries(backup.sha(source)))
            self.assertEqual((dest / 'snapshot-fixture/work.tar.gz').read_text(), 'fixture')
            item = entries('wrong')
            try:
                with self.assertRaises(ValueError): backup.publish(dest, item)
            finally: os.close(item['files'][0]['fd'])
            item = entries('wrong'); item['name'] = 'snapshot-bad'
            with self.assertRaises(ValueError): backup.publish(dest, item)
            self.assertFalse((dest / 'snapshot-bad').exists())
            self.assertFalse(list(dest.glob('.incoming-*')))


if __name__ == '__main__':
    unittest.main()
