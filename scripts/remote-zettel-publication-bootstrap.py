"""One-time operator bootstrap before the first software task/publication.

All code, topology, source objects, commits and public-key bytes are pinned by
the operator package. Existing source/credential/authority identities are never
replaced. A failed stage remains stopped with its exact receipts for inspection.
"""
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import grp
import pwd
import sqlite3
import stat
import subprocess
import sys
import time

STAGE = 'input'
ERROR_ROOT = None


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def run(argv, timeout=120):
    try:
        return subprocess.check_output(list(map(str, argv)), stdin=subprocess.DEVNULL,
            stderr=subprocess.PIPE, timeout=timeout, env={'PATH': '/no-tools', 'LC_ALL': 'C'}, text=True)
    except subprocess.CalledProcessError as error:
        if ERROR_ROOT is not None:
            path = ERROR_ROOT / ('bootstrap-error-' + STAGE + '-' + str(time.time_ns()) + '.log')
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            try:
                os.write(fd, error.stderr[:16384].encode())
                os.fsync(fd)
            finally:
                os.close(fd)
        raise


def load_install(path):
    spec = importlib.util.spec_from_file_location('install', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def empty_coordinator(path, uid, documents_root='/var/lib/remote-zettel/work-instances/remote-zettel/documents'):
    tasks = Path(documents_root) / 'tasks'
    if os.path.lexists(tasks):
        if tasks.is_symlink() or not tasks.is_dir() or any(tasks.iterdir()):
            raise ValueError('Software task documents already exist; bootstrap is no longer eligible')
    path = Path(path)
    if not path.exists():
        return
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_nlink != 1:
        raise ValueError('Unsafe software coordinator')
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    try:
        if db.execute('PRAGMA quick_check').fetchone() != ('ok',):
            raise ValueError('Software coordinator integrity check failed')
        for table in ('observations', 'task_observation_events', 'task_revision_documents', 'work_runs'):
            if db.execute(f'SELECT 1 FROM {table} LIMIT 1').fetchone():
                raise ValueError('Software work already exists; bootstrap is no longer eligible')
    finally:
        db.close()


def advance_bootstrap(install, root, configuration, pack_root, manifest):
    """Exact fast-forward, only while the web/software owners are stopped."""
    source = Path(configuration['repository'])
    state = Path(configuration['stateDirectory'])
    base, ref = state / 'base', source / '.git/refs/heads/publication-base'
    old, new = manifest['oldBase'], manifest['newBase']
    intent = {'version': 1, 'oldBase': old, 'newBase': new, 'pack': str(pack_root),
              'kind': 'operator-before-first-software-task'}
    receipt = root / 'source-bootstrap-intent.json'
    durable(install, receipt, intent)
    lock_path = source / '.git/publication-source.ownership.sqlite'
    install.read_regular(lock_path, 0)
    lock = sqlite3.connect(lock_path.as_uri() + '?mode=rw', uri=True, timeout=0)
    try:
        lock.execute('BEGIN EXCLUSIVE')
        pointers = [install.read_regular(path, 0, 41)[0] for path in (base, ref)]
        before, after = ((value + '\n').encode() for value in (old, new))
        if pointers not in ([before, before], [before, after], [after, after]):
            raise ValueError('Source base/ref changed outside this bootstrap')
        for suffix in ('pack', 'idx'):
            raw = (pack_root / ('objects.' + suffix)).read_bytes()
            expected = manifest[suffix]
            if len(raw) != expected['bytes'] or hashlib.sha256(raw).hexdigest() != expected['sha256']:
                raise ValueError('Pinned bootstrap object changed')
            destination = source / '.git/objects/pack' / ('pack-' + manifest['packId'] + '.' + suffix)
            exact_file(install, destination, raw, 0o600)
        # The Git ref becomes durable before exposing the advancing base.
        for path, mode in ((ref, 0o600), (base, 0o644)):
            if install.read_regular(path, 0, 41)[0] == after:
                continue
            temporary = path.with_name('.operator-bootstrap-' + path.name)
            exact_file(install, temporary, after, mode)
            if install.read_regular(path, 0, 41)[0] != before:
                raise ValueError('Source pointer changed during bootstrap')
            os.replace(temporary, path)
            install.sync_dir(path.parent)
        durable(install, root / 'source-bootstrap-complete.json', intent)
    finally:
        lock.close()


def exact_file(install, path, raw, mode, gid=0):
    if os.path.lexists(path):
        actual, info = install.read_regular(path, 0, len(raw))
        if actual != raw or stat.S_IMODE(info.st_mode) != mode or info.st_gid != gid:
            raise ValueError('Existing artifact differs: ' + str(path))
    else:
        install.create(path, raw, mode, gid=gid)


def durable(install, path, value):
    exact_file(install, path, canonical(value), 0o600)


def directory(install, path, mode=0o700, gid=0):
    if not os.path.lexists(path):
        install.directory(path, mode, gid=gid)
        return
    install.parents(path, 0)
    info = path.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_gid != gid
            or stat.S_IMODE(info.st_mode) != mode):
        raise ValueError('Existing directory differs: ' + str(path))


def publication_accounts(install, root, systemctl):
    groups = [('rzwi-remote-zettel-importer', 3310), ('rzwi-remote-zettel-publisher', 3311),
              ('rzwi-remote-zettel-pub', 3312), ('rzwi-remote-zettel-bundle', 3313)]
    users = [('rzwi-remote-zettel-importer', 3310, 3313), ('rzwi-remote-zettel-publisher', 3311, 3311)]
    # Match the final declarative publication plan; never reassign an identity.
    for name, gid in groups:
        try:
            if grp.getgrnam(name).gr_gid != gid:
                raise ValueError('Publication group name conflicts')
        except KeyError:
            pass
        try:
            if grp.getgrgid(gid).gr_name != name:
                raise ValueError('Publication group ID conflicts')
        except KeyError:
            pass
    for name, uid, gid in users:
        try:
            info = pwd.getpwnam(name)
            if info.pw_uid != uid or info.pw_gid != gid:
                raise ValueError('Publication user name conflicts')
        except KeyError:
            pass
        try:
            if pwd.getpwuid(uid).pw_name != name:
                raise ValueError('Publication user ID conflicts')
        except KeyError:
            pass
    lines = [f'g {name} {gid}' for name, gid in groups]
    lines += [f'u {name} {uid}:{gid} "Remote Zettel publication" /var/empty -' for name, uid, gid in users]
    path = root / 'commission-users.conf'
    exact_file(install, path, ('\n'.join(lines) + '\n').encode(), 0o600)
    run([str(Path(systemctl).with_name('systemd-sysusers')), path])
    for name, uid, gid in users:
        info = pwd.getpwnam(name)
        if (info.pw_uid, info.pw_gid) != (uid, gid):
            raise ValueError('Publication account was not created as declared')


def bootstrap(binding):
    global STAGE, ERROR_ROOT
    p = json.loads(Path(binding['plan']).read_text())
    root = Path(p['root'])
    install = load_install(binding['install'])
    if str(Path('/run/current-system').resolve()) != binding['system'] or str(Path('/nix/var/nix/profiles/system').resolve()) != binding['system']:
        raise ValueError('Selected/running system changed; rebuild the operator')
    intent = dict(version=1, binding=binding)
    if root.exists() and not (root / 'bootstrap-intent.json').exists():
        raise ValueError('Unknown existing publication root')
    directory(install, root, 0o755)
    durable(install, root / 'bootstrap-intent.json', intent)
    ERROR_ROOT = root
    if (root / 'bootstrap-complete.json').exists():
        if json.loads(install.read_regular(root / 'bootstrap-complete.json', 0)[0]) != intent:
            raise ValueError('Completed bootstrap binding changed')
        print('Publication bootstrap already completed; no changes made.')
        return
    key = Path(json.loads(Path(p['sshConfiguration']).read_text())['credential'])
    key_receipt = root / 'key-installed.json'
    if not key_receipt.exists():
        if os.path.lexists(key.parent):
            raise ValueError('Unknown existing credential directory')
        raw, info = install.read_regular(Path(binding['keySource']), 1000, 16384)
        if stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('Private operator key required')
        if ' '.join(run([p['sshKeygen'], '-y', '-f', binding['keySource']]).split()[:2]) != binding['publicKey']:
            raise ValueError('Operator key does not match the enrolled public key')
        directory(install, key.parent)
        install.create(key, raw, 0o400)
        durable(install, key_receipt, {'publicKey': binding['publicKey']})
    if ' '.join(run([p['sshKeygen'], '-y', '-f', key]).split()[:2]) != binding['publicKey']:
        raise ValueError('Installed key changed')
    # This one-time transition is only available before any software task exists.
    empty_coordinator(binding['coordinator'], p['applicationUid'])
    units = ['remote-zettel.service'] + ['remote-zettel-work-instance-remote-zettel-' + suffix + '.service'
        for suffix in ('host', 'executor-supervisor', 'proxy', 'content-proxy', 'repository-read')]
    running_path = root / 'stopped-services.json'
    if not running_path.exists():
        running = [unit for unit in units if subprocess.call([p['systemctl'], 'is-active', '--quiet', unit]) == 0]
        durable(install, running_path, running)
    STAGE = 'service-stop'
    run([p['systemctl'], 'stop', *units])
    empty_coordinator(binding['coordinator'], p['applicationUid'])
    STAGE = 'source-verification'
    run([binding['sourceVerifier'], '--verify'])
    pack_root = Path(binding['pack'])
    advance_bootstrap(install, root, p['reusable']['sourceConfiguration'], pack_root,
                      json.loads((pack_root / 'manifest.json').read_text()))
    run([binding['sourceVerifier'], '--verify'])
    STAGE = 'account-creation'
    publication_accounts(install, root, p['systemctl'])
    config_dir = root / 'config'
    directory(install, config_dir, 0o750, p['applicationGid'])
    directory(install, root / 'publisher')
    request = {name: p[name] for name in ('repository', 'repositoryId', 'generation', 'enrollment', 'ingestionPin',
        'sshConfiguration', 'knownHosts', 'connection', 'access', 'reusable', 'publisherUid', 'releaseSocket')}
    request.update(version=2, targetSystem=binding['system'], human=binding['human'],
        sourceId=hashlib.sha256(b'remote-zettel-software-publication-source-v1').hexdigest(),
        publisherId=hashlib.sha256(b'remote-zettel-software-publisher-v1').hexdigest(),
        promotionDirectory=p['ingestionDirectory'], storePath=p['publisherStorePath'],
        promotionSocket=p['publicationPaths']['receipt'], promotionServerUid=0,
        releaseServerUid=p['applicationUid'], objectSocketPath=p['publicationPaths']['objects'], objectServerUid=0,
        outcomeSocket=p['publicationPaths']['outcome'], outputDirectory=str(root / 'commissioned'),
        credentialProvisioningAuthorized=True)
    request_file = root / 'commission.json'
    durable(install, request_file, request)
    if not (root / 'commissioned').exists():
        STAGE = 'configuration-commissioning'
        run([p['commissioner'], request_file])
    complete = json.loads(install.read_regular(root / 'commissioned/complete.json', 0)[0])
    if complete['targetSystem'] != binding['system']:
        raise ValueError('Commissioner target changed')
    for name, destination, mode, gid in [
        ('approval.json', p['approvalConfigurationFile'], 0o644, p['applicationGid']),
        ('operator.json', p['publisherConfigurationFile'], 0o600, 0),
        ('ingestion.json', p['ingestionWriterConfigurationFile'], 0o600, 0)]:
        raw, _ = install.read_regular(root / 'commissioned' / name, 0, expected=complete['files'][name])
        exact_file(install, Path(destination), raw, mode, gid)
    pin = json.loads(Path(p['ingestionPin']).read_text())
    service = dict(version=2, kind='work-candidate-ingestion-service-v2',
        ingestionConfig=p['ingestionWriterConfigurationFile'], policySha256=pin['policyDigest'],
        intakeSocket=p['reusable']['ingestion']['socketPath'], intakeUid=p['applicationUid'],
        receiptSocket=p['publicationPaths']['receipt'], receiptUid=p['applicationUid'],
        objectSocket=p['publicationPaths']['objects'], objectUid=0)
    exact_file(install, Path(p['ingestionConfigurationFile']), canonical(service), 0o600)
    ingestion = Path(p['ingestionDirectory'])
    directory(install, ingestion)
    operation = '--check-ingestion' if (ingestion / 'promotions.sqlite').exists() else '--initialize-ingestion'
    STAGE = 'ingestion-initialization'
    run([p['ingest'], operation, p['ingestionConfigurationFile']], timeout=180)
    operation = 'status' if Path(p['publisherStorePath']).exists() else 'initialize'
    STAGE = 'publisher-initialization'
    run([p['node'], p['application'] + '/src/cli/work-publication.js', p['publisherConfigurationFile'], operation])
    operator = json.loads(install.read_regular(Path(p['publisherConfigurationFile']), 0)[0])
    public = Path(p['root'] + '-enrollment')
    directory(install, public, 0o755)
    exact_file(install, public / 'policy.json', canonical({
        'publication': operator['outcomePolicy'], 'owner': operator['ownerPolicy'],
        'sourceBase': json.loads((pack_root / 'manifest.json').read_text())['newBase'],
        'publicKey': binding['publicKey']}), 0o644)
    running = json.loads(install.read_regular(running_path, 0)[0])
    if running:
        STAGE = 'service-restart'
        run([p['systemctl'], 'start', *running])
    durable(install, root / 'bootstrap-complete.json', intent)
    print('Software publisher commissioned; prior services restarted. Publication/deployment services remain disabled.')


if __name__ == '__main__':
    try:
        if os.geteuid() != 0 or not sys.flags.isolated or len(sys.argv) != 2:
            raise ValueError('Root isolated operator invocation required')
        lock = os.open('/run/remote-zettel-software-publication-bootstrap.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        bootstrap(json.loads(Path(sys.argv[1]).read_text()))
    except Exception as error:
        # Subprocess stderr may contain private input; never relay it.
        print('Software publication bootstrap stopped: ' + (str(error) if not isinstance(error, subprocess.SubprocessError)
              else 'trusted subprocess failed during ' + STAGE + '; a private diagnostic is retained in the publication root'), file=sys.stderr)
        raise SystemExit(1)
