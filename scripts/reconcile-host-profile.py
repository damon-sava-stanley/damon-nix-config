#!/usr/bin/env python3
"""Reconcile only the observed failed switch; never activate the failed target."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import socket
import sqlite3
import stat
import subprocess
import sys
import time

RUNNING = '/nix/store/jczv8zybgjkdaag30kc7fv1bg6gaig28-nixos-system-deeley-26.05.20261113.f1e5c35'
FAILED = '/nix/store/4b1j492kxig1ljl9d0gh57q20ailap7f-nixos-system-deeley-26.05.20261118.3457b69'
CURRENT = Path('/run/current-system')
PROFILE = Path('/nix/var/nix/profiles/system')
STATE = Path('/var/lib/remote-zettel-host-maintenance')
BIN = Path(RUNNING) / 'sw/bin'
BRIDGE = 'remote-zettel-deployment-bridge.service'
TERMINAL = {'succeeded', 'build-failed', 'authorization-failed'}
ENV = {'PATH': str(BIN), 'LANG': 'C.UTF-8'}


def run(*args, timeout=120):
    return subprocess.check_output(list(map(str, args)), cwd='/', env=ENV,
                                   text=True, timeout=timeout).strip()


def protected(path, directory=False):
    path = Path(path)
    for parent in reversed(path.parents):
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            # Nix store is a root-owned sticky directory on this host.
            if not (parent == Path('/nix/store') and info.st_uid == 0
                    and stat.S_ISDIR(info.st_mode) and info.st_mode & stat.S_ISVTX):
                raise ValueError('Unprotected ancestor: ' + str(parent))
    info = path.lstat()
    if (info.st_uid != 0 or info.st_gid != 0 or info.st_mode & 0o077
            or (not stat.S_ISDIR(info.st_mode) if directory else
                not stat.S_ISREG(info.st_mode) or info.st_nlink != 1)):
        raise ValueError('Unprotected state: ' + str(path))
    return path


def durable(path, value):
    raw = json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    if path.exists() or path.is_symlink():
        if protected(path).read_bytes() != raw:
            raise ValueError('Conflicting maintenance receipt: ' + str(path))
        return
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        os.write(fd, raw)
        os.fsync(fd)
    finally:
        os.close(fd)
    sync(path.parent)


def sync(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def selections():
    running, selected = str(CURRENT.resolve(strict=True)), str(PROFILE.resolve(strict=True))
    if running != RUNNING or selected not in (FAILED, RUNNING):
        raise ValueError('System selection changed; inspect again before reconciliation')
    return {'running': running, 'selected': selected}


@contextlib.contextmanager
def database(path):
    protected(path)
    db = sqlite3.connect(Path(path).as_uri() + '?mode=ro', uri=True, timeout=0)
    try:
        db.execute('BEGIN')
        if db.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
            raise ValueError('Journal integrity check failed')
        yield db
    finally:
        db.close()


def journals(bridge):
    controller = Path(bridge['controllerStateDirectory']) / 'state.sqlite'
    configuration = json.loads(Path(bridge['controllerConfigurationFile']).read_text())
    for key in ('adapterCommand', 'verifierCommand'):
        configuration[key] = str(Path(configuration[key]).resolve(strict=True))
    policy = hashlib.sha256(json.dumps(configuration, sort_keys=True,
        separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
    records = {}
    with database(controller) as db:
        if db.execute('SELECT digest FROM policy').fetchall() != [(policy,)]:
            raise ValueError('Controller journal does not match the running policy')
        rows = db.execute('SELECT id, record FROM deployments').fetchall()
        for identifier, raw in rows:
            record = json.loads(raw)
            if (record['state'] not in TERMINAL or record['policyDigest'] != policy
                    or record['request']['deploymentId'] != identifier):
                raise ValueError('Unsettled or conflicting deployment; reconcile with the controller first')
            records[identifier] = record
    delivered = 0
    with database(Path(bridge['deliveryStatePath'])) as db:
        bindings = db.execute('SELECT singleton, policy FROM deployment_delivery_contract').fetchall()
        if len(bindings) != 1 or bindings[0][0] != 1:
            raise ValueError('Invalid delivery contract')
        contract = json.loads(bindings[0][1])
        if contract != dict(version=1, target=bridge['target'], controllerPolicyDigest=policy,
                            publication=bridge['publication'], owner=bridge['owner']):
            raise ValueError('Delivery journal does not match the running policy')
        for raw_request, raw_ack in db.execute('SELECT request, acknowledgment FROM deployment_delivery'):
            if raw_ack is None:
                raise ValueError('Deployment delivery has a pending handoff')
            request, ack = json.loads(raw_request), json.loads(raw_ack)
            if (ack['state'] not in TERMINAL or ack['policyDigest'] != policy or ack['request'] != request
                    or records.get(request['deploymentId']) != ack):
                raise ValueError('Delivery acknowledgment does not match its terminal controller receipt')
            delivered += 1
    return {'controllerRecords': len(records), 'settledDeliveries': delivered}


def bridge_state():
    return run(BIN / 'systemctl', 'show', BRIDGE, '--property=ActiveState', '--value')


def reconcile():
    before = selections()
    bridge = json.loads((Path(RUNNING) / 'etc/remote-zettel-self-deployment/bridge.json').read_text())
    protected(Path(bridge['controllerStateDirectory']), directory=True)
    hold = Path(bridge['controllerStateDirectory']) / 'operator-recovery'
    intent = {'operation': 'reconcile-failed-host-switch-v1', 'running': RUNNING, 'failed': FAILED}
    initial_bridge = bridge_state()
    if initial_bridge not in ('active', 'inactive'):
        raise ValueError('Deployment bridge is not in a stable state')
    # Read before asking the bridge to drain. No in-flight deployment is terminated.
    journals(bridge)
    if hold.exists() or hold.is_symlink():
        if protected(hold).read_bytes() != json.dumps(intent, sort_keys=True, separators=(',', ':')).encode():
            raise ValueError('An independent operator recovery hold already exists')
    durable(STATE / 'reconcile-intent.json', intent)
    durable(hold, intent)
    if initial_bridge == 'active':
        # Signal only the main process. Its handler waits for a controller child;
        # systemctl stop would signal the whole cgroup, possibly interrupting activation.
        run(BIN / 'systemctl', 'kill', '--kill-whom=main', '--signal=SIGTERM', BRIDGE)
        deadline = time.monotonic() + 60
        while bridge_state() != 'inactive':
            if time.monotonic() >= deadline:
                raise ValueError('Bridge has not drained; recovery hold retained, no profile change')
            time.sleep(0.5)
    with contextlib.ExitStack() as stack:
        owner = stack.enter_context(open(protected(Path(bridge['controllerStateDirectory']) / 'owner.lock'), 'rb'))
        fcntl.flock(owner.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        ownership_path = protected(Path(bridge['deliveryStatePath'] + '.ownership.sqlite'))
        ownership = sqlite3.connect(ownership_path.as_uri() + '?mode=rw', uri=True, timeout=0)
        stack.callback(ownership.close)
        ownership.execute('BEGIN EXCLUSIVE')
        settled = journals(bridge)
        selections()
        upgrade = json.loads((Path(RUNNING) / 'etc/remote-zettel-work-upgrade.json').read_text())
        run(*shlex.split(upgrade['guardCommand']))
        before_receipt = STATE / 'reconcile-before.json'
        if before_receipt.exists() or before_receipt.is_symlink():
            retained = json.loads(protected(before_receipt).read_text())
            if (retained.get('running') != RUNNING or retained.get('selected') not in (FAILED, RUNNING)
                    or any(retained.get(key) != value for key, value in settled.items())):
                raise ValueError('Retained reconciliation inspection changed')
        else:
            durable(before_receipt, dict(**before, **settled))
        # Select the running generation, never an earlier generation or old database.
        run(BIN / 'nix-env', '--profile', PROFILE, '--set', RUNNING)
        run(Path(RUNNING) / 'bin/switch-to-configuration', 'boot', timeout=180)
        after = selections()
        if after['selected'] != RUNNING:
            raise ValueError('Profile reconciliation did not select the running generation')
        durable(STATE / 'reconcile-complete.json', dict(running=RUNNING, selected=RUNNING))
    print('RECONCILED: selected profile and boot configuration now use the running generation.')
    print('Application/Work services and databases were not rolled back.')
    print('Automatic deployment remains on operator hold while migration is prepared.')
    print('Receipts: ' + str(STATE))
    print(run(BIN / 'bootctl', 'list', '--no-pager'))


def main():
    if os.geteuid() != 0 or not sys.flags.isolated or socket.gethostname() != 'deeley':
        raise ValueError('Run with isolated Python as root on deeley')
    if len(sys.argv) != 1:
        raise ValueError('No arguments accepted')
    os.umask(0o077)
    if not STATE.exists():
        STATE.mkdir(mode=0o700)
        sync(STATE.parent)
    protected(STATE, directory=True)
    fd = os.open(STATE / 'operator.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        protected(STATE / 'operator.lock')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        reconcile()
    finally:
        os.close(fd)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Reconciliation stopped: ' + str(error), file=sys.stderr)
        print('Any created operator hold is retained; no automatic rollback or delivery restart.', file=sys.stderr)
        sys.exit(1)
