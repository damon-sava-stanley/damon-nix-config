#!/usr/bin/env python3
"""Quiescent Work snapshots. No credential reads, live restore, or retention deletion."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import pwd
import shutil
import signal
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
import traceback


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def capture_command(args, timeout):
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    try:
        if process.wait(timeout=timeout):
            raise RuntimeError('Capture failed')
    except BaseException:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as stream:
        json.dump(value, stream)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def rows(path, sql):
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    try:
        return db.execute(sql).fetchall()
    finally:
        db.close()


def verify(archive, database_names):
    """Never extract archive paths or links. Copy only known operational DBs to scratch."""
    with tarfile.open(archive, 'r:*') as tar:
        members = tar.getmembers()
        names = {}
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or path.name.startswith('credentials.sqlite'):
                raise ValueError('Unsafe archive member')
            name = str(path)
            if name in names:
                raise ValueError('Duplicate archive member')
            names[name] = member
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError('Special archive member')
        for name in database_names:
            if name not in names or not names[name].isfile():
                raise ValueError('Missing operational database')
        # Include private host journals and SQLite ownership DBs, never arbitrary
        # databases from agent-writable repositories/documents. Sidecars stay paired.
        parents = {str(PurePosixPath(n).parent) for n in database_names}
        selected = {n: m for n, m in names.items()
                    if str(PurePosixPath(n).parent) in parents and '.sqlite' in PurePosixPath(n).name}
        with tempfile.TemporaryDirectory(dir=archive.parent, prefix='.verify-') as temp:
            for name, member in selected.items():
                if not member.isfile():
                    raise ValueError('Linked operational database')
                parent = Path(temp) / hashlib.sha256(str(PurePosixPath(name).parent).encode()).hexdigest()
                parent.mkdir(exist_ok=True)
                destination = parent / PurePosixPath(name).name
                with tar.extractfile(member) as source, destination.open('wb') as target:
                    shutil.copyfileobj(source, target)
            count = 0
            for path in Path(temp).rglob('*.sqlite'):
                if rows(path, 'PRAGMA integrity_check') != [('ok',)]:
                    raise ValueError('Database integrity failure')
                count += 1
        return {'sqliteDatabases': count, 'members': len(members),
                'retainedLinksNotFollowed': sum(m.issym() or m.islnk() for m in members)}


def publish(destination, entries):
    """Called only after dropping uid/gid; root-private files arrive as read-only FDs."""
    destination = Path(destination)
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    if destination.is_symlink() or destination.stat().st_uid != os.getuid() or destination.stat().st_mode & 0o077:
        raise ValueError('Unsafe publication destination')
    name = entries['name']
    if not name.startswith('snapshot-') or Path(name).name != name:
        raise ValueError('Invalid snapshot name')
    final = destination / name
    if final.exists():
        raise ValueError('Snapshot already exists')
    temporary = Path(tempfile.mkdtemp(prefix='.incoming-', dir=destination))
    try:
        for entry in entries['files']:
            name = entry['name']
            if Path(name).name != name:
                raise ValueError('Invalid bundle filename')
            with os.fdopen(entry['fd'], 'rb') as source, (temporary / name).open('xb') as target:
                shutil.copyfileobj(source, target)
                target.flush()
                os.fsync(target.fileno())
            if sha(temporary / name) != entry['sha256']:
                raise ValueError('Replication checksum mismatch')
        sync_directory(temporary)
        temporary.rename(final)
        fd = os.open(destination, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except BaseException:
        shutil.rmtree(temporary)
        raise


class Backup:
    def __init__(self, config):
        self.config = config
        self.root = Path(config['backupRoot'])
        self.recovery = self.root / 'recovery.json'

    def control(self, action, units):
        subprocess.run(['systemctl', action, *units], check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=180)

    def active(self, unit):
        return subprocess.run(['systemctl', 'is-active', '--quiet', unit], check=False).returncode == 0

    def checks(self):
        c = self.config
        return [
            (Path(c['coordinator']) / 'state.sqlite', "SELECT COUNT(*) FROM work_runs WHERE status IN ('ready','running','cancelling')"),
            (Path(c['host']) / 'admission.sqlite', "SELECT COUNT(*) FROM sequential_runs WHERE status='active'"),
            (Path(c['executor']) / 'runs.sqlite', "SELECT COUNT(*) FROM runs WHERE phase!='settled'"),
            (Path(c['executor']) / 'operations/runs.sqlite', "SELECT COUNT(*) FROM runs WHERE phase!='settled'"),
        ]

    def drained(self):
        return all(rows(path, sql) == [(0,)] for path, sql in self.checks())

    def stop(self, units):
        recorded = json.loads(self.recovery.read_text()) if self.recovery.exists() else []
        atomic_json(self.recovery, list(dict.fromkeys(recorded + units)))
        self.control('stop', units)

    def recover(self):
        if not self.recovery.exists():
            return
        recorded = json.loads(self.recovery.read_text())
        if not isinstance(recorded, list) or any(x not in self.config['units'] for x in recorded):
            raise ValueError('Invalid service recovery record')
        units = [u for u in self.config['units'] if u in recorded]
        if units:
            self.control('start', units)
            if not all(self.active(u) for u in units):
                raise RuntimeError('Service recovery incomplete')
        self.recovery.unlink()
        fd = os.open(self.root, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def capture(self):
        c = self.config
        stage = Path(tempfile.mkdtemp(prefix='.pending-', dir=self.root))
        archive = stage / 'work.tar'
        paths = [c[k] for k in ['documents', 'coordinator', 'host', 'executor', 'source', 'scratch']]
        if any(not Path(p).is_absolute() or '..' in Path(p).parts or Path(p).is_symlink() for p in paths):
            raise ValueError('Invalid snapshot root')
        capture_command(['tar', '--create', '--acls', '--xattrs', '--numeric-owner',
                         '--file=' + str(archive), '--exclude=' + c['host'].lstrip('/') + '/credentials.sqlite*',
                         '--exclude=' + c['host'].lstrip('/') + '/host.sock', '-C', '/',
                         *(p.lstrip('/') for p in paths)], c.get('captureTimeout', 120))
        # Persist only reviewed nonsecret configuration, unit definitions and store references.
        metadata = {'version': 1, 'created': time.time(), 'configuration': c,
                    'generation': str(Path('/run/current-system').resolve()), 'units': {}}
        for unit in c['units']:
            metadata['units'][unit] = subprocess.check_output([
                'systemctl', 'show', unit, '-p', 'FragmentPath', '-p', 'User', '-p', 'Group',
                '-p', 'ProtectHome', '-p', 'ProtectSystem', '-p', 'RootDirectory'], text=True, timeout=10)
        atomic_json(stage / 'metadata.json', metadata)
        return stage

    def validate_and_publish(self, stage):
        subprocess.run(['gzip', '--no-name', str(stage / 'work.tar')], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        archive = stage / 'work.tar.gz'
        result = verify(archive, [str(path).lstrip('/') for path, _ in self.checks()])
        atomic_json(stage / 'verification.json', result)
        files = sorted(stage.iterdir())
        (stage / 'SHA256SUMS').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
        for path in stage.iterdir():
            with path.open('rb') as f:
                os.fsync(f.fileno())
        name = time.strftime('snapshot-%Y%m%dT%H%M%SZ-', time.gmtime()) + stage.name.removeprefix('.pending-')
        final = self.root / name
        sync_directory(stage)
        stage.rename(final)
        sync_directory(self.root)
        owner = pwd.getpwnam(self.config['owner'])
        fds = []
        try:
            entries = []
            for path in sorted(final.iterdir()):
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                fds.append(fd)
                entries.append({'name': path.name, 'fd': fd, 'sha256': sha(path)})
            subprocess.run([sys.executable, str(Path(__file__).resolve()), '--publish', self.config['destination']],
                           input=json.dumps({'name': name, 'files': entries}), text=True,
                           pass_fds=fds, user=owner.pw_uid, group=owner.pw_gid, extra_groups=[],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        finally:
            for fd in fds:
                os.close(fd)
        return name

    def run(self):
        if self.recovery.exists():
            self.recover()
        if not all(self.active(unit) for unit in self.config['units']):
            return 'skipped-services-inactive'
        if not self.drained():
            return 'skipped-busy'
        try:
            self.stop([self.config['webUnit']])
            if not self.drained():
                return 'skipped-admission-race'
            self.stop([u for u in self.config['units'] if u != self.config['webUnit']])
            if any(self.active(u) for u in self.config['units']):
                raise RuntimeError('Service did not stop')
            if not self.drained():
                raise RuntimeError('Stopped stores not drained')
            stage = self.capture()
        finally:
            self.recover()
        # Resume service before costly verification and Dropbox replication.
        name = self.validate_and_publish(stage)
        return 'completed:' + name


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config')
    parser.add_argument('--recover', action='store_true')
    parser.add_argument('--publish')
    args = parser.parse_args()
    os.umask(0o077)
    if args.publish:
        if os.getuid() == 0 or os.geteuid() == 0 or os.getgroups():
            raise ValueError('Publication must run unprivileged without supplementary groups')
        capabilities = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines() if line.startswith(('CapEff:', 'CapPrm:', 'CapAmb:')))
        if any(int(value.strip(), 16) for value in capabilities.values()):
            raise ValueError('Publication must have no capabilities')
        publish(args.publish, json.loads(sys.stdin.read(65536)))
        return
    if os.geteuid() != 0:
        raise ValueError('Snapshot requires root')
    config = json.loads(Path(args.config).read_text())
    b = Backup(config)
    b.root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if b.root.is_symlink() or b.root.stat().st_uid != 0 or b.root.stat().st_mode & 0o077:
        raise ValueError('Backup root must be root-private')
    with (b.root / 'owner.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if args.recover:
                raise RuntimeError('Recovery lock busy')
            print('Work backup already running')
            return
        if args.recover:
            b.recover()
            status_path = b.root / 'status.json'
            if status_path.exists():
                status = json.loads(status_path.read_text())
                if status.get('result') == 'running':
                    status['result'] = 'interrupted'
                    atomic_json(status_path, status)
            return
        old = json.loads((b.root / 'status.json').read_text()) if (b.root / 'status.json').exists() else {}
        atomic_json(b.root / 'status.json', {'attempted': time.time(), 'result': 'running', 'lastCompleted': old.get('lastCompleted')})
        signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(InterruptedError()))
        try:
            result = b.run()
            old = json.loads((b.root / 'status.json').read_text()) if (b.root / 'status.json').exists() else {}
            status = {'attempted': time.time(), 'result': result, 'lastCompleted': old.get('lastCompleted')}
            if result.startswith('completed:'):
                status['lastCompleted'] = {'time': time.time(), 'snapshot': result.split(':', 1)[1]}
            atomic_json(b.root / 'status.json', status)
            print('Work backup: ' + result)
        except BaseException:
            (b.root / 'last-error.txt').write_text(traceback.format_exc())
            old = json.loads((b.root / 'status.json').read_text()) if (b.root / 'status.json').exists() else {}
            atomic_json(b.root / 'status.json', {'attempted': time.time(), 'result': 'failed', 'lastCompleted': old.get('lastCompleted')})
            print('Work backup failed; inspect private state and service health', file=sys.stderr)
            sys.exit(1)


if __name__ == '__main__':
    main()
