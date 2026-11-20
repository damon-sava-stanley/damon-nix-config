#!/usr/bin/env python3
"""Exact before-first-task source fast-forward, then one genuine Work test task.

No enrollment changes, credential copying, synthetic approvals or forced pushes.
"""
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import sqlite3
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

EMPTY_TABLES = {'observations', 'task_observation_events', 'task_revision_documents',
    'work_runs', 'work_preparation_attempts', 'work_approval_packages', 'work_approval_decisions',
    'work_publication_outbox', 'work_publication_reservations', 'work_publication_completions',
    'work_task_closeout', 'sequential_runs', 'cleaned_runs', 'continuation_edges', 'runs',
    'checks', 'reviews', 'attempts', 'admissions', 'publication_owner_history',
    'publication_owner_reservation', 'publication_owner_retirements', 'deployments',
    'deployment_delivery', 'workspaces', 'operations', 'captures', 'validations', 'cleanup_requests'}

def fresh_databases(u, paths):
    for path in paths:
        with u.database(path) as db:
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            for table in sorted(tables & EMPTY_TABLES):
                if db.execute('SELECT 1 FROM "' + table + '" LIMIT 1').fetchone():
                    raise ValueError('Software/deployment history exists; before-first-task advance refused')

def release_fences(h, state, units):
    u = h.upgrade
    identities = u.read(state / 'fences.json')
    if set(identities) != set(units):
        raise ValueError('Source-maintenance fence inventory changed')
    for unit, identity in identities.items():
        path = u.CONTROL / unit
        if not os.path.lexists(path):
            continue  # Source-ready receipt authorizes interrupted selective release.
        info = path.lstat()
        if info.st_uid != 0 or not stat.S_ISLNK(info.st_mode) or os.readlink(path) != '/dev/null' or [info.st_dev, info.st_ino] != identity:
            raise ValueError('Source-maintenance fence changed')
    for unit in units:
        path = u.CONTROL / unit
        if os.path.lexists(path):
            path.unlink()
    u.install.sync_dir(u.CONTROL)

def main():
    if os.geteuid() != 0 or not sys.flags.isolated or len(sys.argv) != 2:
        raise ValueError('Root isolated immutable invocation required')
    os.umask(0o077)
    h = load('host', '/nix/store/f92c9dbzqfgkcc8v7gwvr0w252p8szc9-work-host-policy-upgrade-scripts/work-host-policy-upgrade.py')
    p = h.manifest(sys.argv[1]); u = h.upgrade
    p['manifest'] = sys.argv[1]
    b = load('bootstrap', p['bootstrapHelper'])
    ready = load('readiness', p['readinessHelper'])
    state = Path(p['stateDirectory'])
    lock = os.open('/run/remote-zettel-host-policy-upgrade.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        expected = {'planDigest': p['manifestDigest'], 'oldBase': p['oldBase'], 'newBase': p['newBase']}
        if (state / 'started.json').exists():
            started = u.read(state / 'started.json')
            if started['planDigest'] != p['manifestDigest']:
                raise ValueError('Recorded release test belongs to another plan')
            print('Release test already queued: ' + started['runId'])
            print('Status: ' + p['observerDirectory'] + '/status.json')
            return
        if os.path.realpath('/run/current-system') != p['system'] or os.path.realpath('/nix/var/nix/profiles/system') != p['system']:
            raise ValueError('Host changed before release test')
        u.mkdir(state)
        u.durable(state / 'intent.json', expected)
        def work(args, timeout=60):
            # Mutations are attempted once, from a directory accessible to the
            # application UID; durable intent handles an uncertain reply.
            return json.loads(subprocess.check_output([p['runuser'], '-u', 'remote-zettel', '--', p['workCli'],
                '--socket', p['controlSocket'], *args], stdin=subprocess.DEVNULL, stderr=subprocess.PIPE,
                cwd='/', env=u.ENV, timeout=timeout, text=True))
        def fresh():
            b.empty_coordinator(p['coordinatorStatePath'], p['webUid'], p['documentsRoot'])
            paths = [Path(p['coordinatorStatePath']), Path(p['hostRoot']) / 'admission.sqlite', Path(p['publisherStorePath']),
                Path(p['bridge']['controllerStateDirectory']) / 'state.sqlite', Path(p['bridge']['deliveryStatePath'])]
            paths += [x for x in Path(p['executorRoot']).rglob('*.sqlite') if not x.name.endswith('.ownership.sqlite')]
            paths += list(Path(p['ingestionDirectory']).glob('promotions.sqlite'))
            if len(paths) > 128:
                raise ValueError('Database inspection budget exceeded')
            fresh_databases(u, paths)
        if not (state / 'restored.json').exists():
            if not (state / 'source-ready.json').exists():
                fresh()
                h.controller_drain({'previousBridge': p['bridge']})
                before = Path(p['baseFile']).read_text().strip()
                if before != p['oldBase'] and not (state / 'source-bootstrap-intent.json').exists():
                    raise ValueError('Source base advanced without this recorded bootstrap')
            hold = Path(p['hold'])
            marker = {'kind': 'before-first-software-task-release-test', 'planDigest': p['manifestDigest']}
            u.durable(hold, marker)
            if not (state / 'source-ready.json').exists():
                status = u.run([p['systemctl'], 'show', 'remote-zettel-deployment-bridge.service', '--property=ActiveState', '--value']).strip()
                if status == 'active':
                    u.run([p['systemctl'], 'kill', '--kill-whom=main', '--signal=SIGTERM', 'remote-zettel-deployment-bridge.service'])
                    end = time.monotonic() + 60
                    while u.run([p['systemctl'], 'show', 'remote-zettel-deployment-bridge.service', '--property=ActiveState', '--value']).strip() != 'inactive':
                        if time.monotonic() >= end:
                            raise ValueError('Deployment bridge did not drain; source was not advanced')
                        time.sleep(0.5)
                elif status != 'inactive':
                    raise ValueError('Deployment bridge is not settled')
                retained = h.quiet(p)
                identities = h.reserve_masks(p, state, p['units'])
                u.run([p['systemctl'], 'daemon-reload'])
                u.run([p['systemctl'], 'stop', 'remote-zettel.service'])
                fresh()
                u.run([p['systemctl'], 'stop', *[v for v in p['units'] if '@' not in v], *retained], 180)
                h.quiet(p, stopped=True)
                fresh()
                h.controller_drain({'previousBridge': p['bridge']})
                with contextlib.ExitStack() as locks:
                    owner = os.open(Path(p['bridge']['controllerStateDirectory']) / 'owner.lock', os.O_RDONLY | os.O_NOFOLLOW)
                    locks.callback(os.close, owner); fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    db = sqlite3.connect(Path(p['bridge']['deliveryStatePath'] + '.ownership.sqlite').as_uri() + '?mode=rw', uri=True, timeout=0)
                    locks.callback(db.close); db.execute('BEGIN EXCLUSIVE')
                    fresh()
                    pin = u.install.read_regular(Path(p['sourcePin']), 0)[0]
                    u.durable(state / 'source-policy.json', {'sha256': hashlib.sha256(pin).hexdigest()})
                    manifest = json.loads(Path(p['packRoot'], 'manifest.json').read_text())
                    if (manifest['oldBase'], manifest['newBase']) != (p['oldBase'], p['newBase']):
                        raise ValueError('Reviewed source pack binding changed')
                    b.advance_bootstrap(u.install, state, p['sourceConfiguration'], Path(p['packRoot']), manifest)
                    if u.install.read_regular(Path(p['sourcePin']), 0)[0] != pin:
                        raise ValueError('Source enrollment changed during advancement')
                    u.run([p['sourceVerifier'], '--verify'])
                    u.durable(state / 'source-ready.json', expected)
            elif u.read(state / 'source-ready.json') != expected:
                raise ValueError('Source-ready receipt changed')
            release_fences(h, state, p['units'])
            u.run([p['systemctl'], 'daemon-reload'])
            u.run([p['systemctl'], 'start', *p['startUnits']], 180)
            command = [p['runuser'], '-u', 'remote-zettel', '--', p['workCli'], '--socket', p['controlSocket'], 'board']
            ready.wait_for_work_board(lambda seconds: ready.read_board_command(command, u.ENV, seconds), p['repositories'])
            u.run([p['sourceVerifier'], '--verify'])
            if u.read(hold) != marker:
                raise ValueError('Independent maintenance hold replaced this attempt')
            hold.unlink(); u.install.sync_dir(hold.parent)
            u.run([p['systemctl'], 'start', 'remote-zettel-deployment-bridge.service'])
            u.durable(state / 'restored.json', expected)
        if Path(p['baseFile']).read_text().strip() != p['newBase']:
            raise ValueError('Source changed before the test task was queued')
        u.run([p['runuser'], '-u', 'remote-zettel', '--', p['python'], '-I', p['taskHelper'], p['manifest']])
        board = work(['board'])
        task = next(t for t in board['tasks'] if t['id'] == p['taskId'])
        if task['revision'] != p['taskRevision'] or task['repository'] != p['repository']:
            raise ValueError('Test task was edited; no work was queued')
        runs = [r for r in board.get('runs', []) if r['taskId'] == p['taskId']]
        if len(runs) > 1:
            raise ValueError('Multiple task runs require separate inspection')
        if runs:
            run = runs[0]
        elif (state / 'queue-intent.json').exists():
            raise ValueError('Queue result is uncertain; inspect the board before another mutation')
        else:
            u.durable(state / 'queue-intent.json', {'taskId': p['taskId'], 'revision': p['taskRevision']})
            run = work(['tasks', 'queue', p['taskId'], '--file', p['queueInput']], 90)
        u.mkdir(p['observerDirectory'], 0o755, p['webUid'], p['webGid'])
        u.run([p['systemdRun'], '--collect', '--unit=remote-zettel-app-release-test', '--uid=remote-zettel', '--gid=remote-zettel',
            '--property=RuntimeMaxSec=7200', '--property=NoNewPrivileges=yes', '--property=ProtectSystem=strict',
            '--property=ProtectHome=yes', '--property=PrivateNetwork=yes', '--property=UMask=0022', '--property=ReadWritePaths=' + p['observerDirectory'],
            p['python'], '-I', p['observerHelper'], p['manifest']], 30)
        u.durable(state / 'started.json', {'planDigest': p['manifestDigest'], 'taskId': p['taskId'], 'runId': run['id']})
        print('RELEASE TEST QUEUED: ' + p['taskId'])
        print('Run: ' + run['id'])
        print('Review and human approval: https://zettel.ss-damon.com/#work')
        print('Read-only progress: ' + p['observerDirectory'] + '/status.json')
    finally:
        os.close(lock)

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Release test stopped: ' + str(error), file=sys.stderr)
        print('Preserve any maintenance hold and fences; do not reset state or synthesize approval.', file=sys.stderr)
        raise SystemExit(1)
