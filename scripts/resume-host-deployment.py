#!/usr/bin/env python3
"""Finish the recorded host transition; never publish or rewrite old journals."""
import fcntl
import hashlib
import importlib.util
import json
import os
import signal
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def inventory(directory):
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('Unprotected journal directory')
    result = {}
    for path in sorted(directory.iterdir()):
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_gid != 0 or info.st_nlink != 1 or info.st_mode & 0o077:
            raise ValueError('Unexpected staged journal entry')
        with path.open('rb') as stream:
            result[path.name] = hashlib.file_digest(stream, 'sha256').hexdigest()
    return result


def install_journals(u, state, bridge, initialize):
    """Seal complete journals before the first rename; resume either rename."""
    receipt = state / 'journals-sealed.json'
    destinations = [Path(bridge['controllerStateDirectory']), Path(bridge['deliveryStatePath']).parent]
    if receipt.exists():
        sealed = u.read(receipt)
        if sealed['destinations'] != list(map(str, destinations)):
            raise ValueError('Journal installation destinations changed')
        stage = Path(sealed['stage'])
        if stage.parent != state or not stage.name.startswith('journal-stage-'):
            raise ValueError('Invalid retained staging reservation')
    else:
        if any(os.path.lexists(path) for path in destinations):
            raise ValueError('Journal namespace exists without its sealed installation receipt')
        stage = Path(tempfile.mkdtemp(prefix='journal-stage-', dir=state))
        for name in ('controller', 'delivery'):
            u.mkdir(stage / name)
        initialize(stage)
        files = [inventory(stage / name) for name in ('controller', 'delivery')]
        if set(files[0]) != {'owner.lock', 'state.sqlite'} or set(files[1]) != {'delivery.sqlite', 'delivery.sqlite.ownership.sqlite'}:
            raise ValueError('Unexpected commissioned journal inventory')
        for name in ('controller', 'delivery'):
            for path in (stage / name).iterdir():
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
            u.install.sync_dir(stage / name)
        u.install.sync_dir(stage)
        sealed = {'stage': str(stage), 'destinations': list(map(str, destinations)), 'files': files}
        u.durable(receipt, sealed)
    for index, name in enumerate(('controller', 'delivery')):
        source, destination = stage / name, destinations[index]
        if os.path.lexists(destination):
            if source.exists() or inventory(destination) != sealed['files'][index]:
                raise ValueError('Installed journal differs from its sealed reservation')
        else:
            if inventory(source) != sealed['files'][index]:
                raise ValueError('Staged journal integrity changed')
            os.rename(source, destination)
            u.install.sync_dir(stage)
            u.install.sync_dir(destination.parent)
    u.durable(state / 'journals-installed.json', {'destinations': sealed['destinations']})


def check_work(h, p):
    for name in ('remote-zettel-work-upgrade.json', 'remote-zettel-host-software-transition.json', 'remote-zettel-work-generation.json'):
        source = Path(p['sourceSystem']) / 'etc' / name
        target = Path(p['targetSystem']) / 'etc' / name
        if source.read_bytes() != target.read_bytes():
            raise ValueError('Final host would change an already commissioned Work contract')
    primary = h.manifest(str(Path(p['targetSystem']) / 'etc/remote-zettel-work-upgrade.json'))
    h.upgrade.guard(primary)
    h.verify_secondary(h.manifest(str(Path(p['targetSystem']) / 'etc/remote-zettel-host-software-transition.json')))


def empty_journals(h, bridge):
    h.controller_drain({'previousBridge': bridge})
    for path, table in [(Path(bridge['controllerStateDirectory']) / 'state.sqlite', 'deployments'),
                        (Path(bridge['deliveryStatePath']), 'deployment_delivery')]:
        with h.upgrade.database(path) as db:
            if db.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0]:
                raise ValueError('New deployment namespace already contains release history')



def read_board_command(command, env, timeout):
    # A board read is safe to retry. Bound each attempt and its descendants;
    # never apply this retry loop to a Work mutation.
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, env=env, cwd="/", start_new_session=True)
    try:
        output, _ = child.communicate(timeout=timeout)
        if child.returncode:
            raise subprocess.CalledProcessError(child.returncode, command)
        return output
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()
        child.stdout.close()


def wait_for_work_board(probe, repositories, timeout=30):
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Work control did not become ready before the deadline; recovery hold retained')
        try:
            board = json.loads(probe(min(5, remaining)))
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        else:
            if not isinstance(board, dict) or not isinstance(board.get('repositories'), list):
                raise ValueError('Invalid Work readiness response; recovery hold retained')
            if set(board['repositories']) != set(repositories):
                raise ValueError('Unexpected Work repository enrollment; recovery hold retained')
            return board
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(0.5, remaining))


def main():
    if os.geteuid() != 0 or not sys.flags.isolated or len(sys.argv) != 2:
        raise ValueError('Isolated root invocation with immutable plan required')
    os.umask(0o077)
    raw = Path(sys.argv[1]).read_bytes()
    p = json.loads(raw)
    if not str(Path(sys.argv[1])).startswith('/nix/store/'):
        raise ValueError('Immutable resume plan required')
    h = load('host_upgrade', p['previousOperatorScripts'] + '/work-host-policy-upgrade.py')
    p = h.manifest(sys.argv[1])
    u = h.upgrade
    lock = os.open('/run/remote-zettel-host-policy-upgrade.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = Path(p['stateDirectory'])
        expected = {'planDigest': p['manifestDigest'], 'targetSystem': p['targetSystem']}
        if (state / 'complete.json').exists():
            if u.read(state / 'complete.json') != expected:
                raise ValueError('Completed deployment resume belongs to another plan')
            print('Automatic deployment was already resumed by this exact plan.')
            return
        running = os.path.realpath('/run/current-system')
        selected = os.path.realpath('/nix/var/nix/profiles/system')
        if running not in (p['sourceSystem'], p['targetSystem']) or selected not in (running, p['targetSystem']):
            raise ValueError('Running/selected host changed before deployment resume')
        if selected != running and u.read(state / 'switch-intent.json') != expected:
            raise ValueError('Unrecorded partial system selection')
        previous = h.manifest(p['previousPlan'])
        done = u.read(Path(previous['stateDirectory']) / 'switched.json')
        if done != {'planDigest': previous['manifestDigest'], 'sourceSystem': previous['sourceSystem'], 'targetSystem': p['sourceSystem']}:
            raise ValueError('The preceding host migration was not completed')
        check_work(h, p)
        bridge = json.loads(Path(p['bridgeConfiguration']).read_text())
        public = u.read(p['publicPolicy'])
        if public != {'publication': bridge['publication'], 'owner': bridge['owner']}:
            raise ValueError('Protected commissioned publication policy differs from final bridge')
        u.mkdir(state)
        u.durable(state / 'intent.json', expected)
        hold = Path(previous['recoveryHold'])
        if hold.exists():
            if hashlib.sha256(u.install.read_regular(hold, 0, 4096)[0]).hexdigest() != previous['recoveryHoldSha256']:
                raise ValueError('Recovery hold changed')
        elif not (state / 'release-intent.json').exists() or running != p['targetSystem']:
            raise ValueError('Recovery hold is missing before verified activation')
        def runtime(operation, staging=None):
            return json.loads(u.run([p['node'], p['runtimeHelper'], p['application'], p['bridgeConfiguration'], operation]
                + ([] if staging is None else [str(staging)]), 30))
        if not (state / 'journals-installed.json').exists():
            observed = subprocess.run([p['systemctl'], 'is-active', 'remote-zettel-deployment-bridge.service'],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=u.ENV, timeout=10)
            if observed.stdout.strip() not in ('inactive', 'failed', 'unknown'):
                raise ValueError('Deployment bridge is not stopped')
            def initialize(stage):
                c = json.loads(Path(bridge['controllerConfigurationFile']).read_text())
                for key in ('adapterCommand', 'verifierCommand'):
                    c[key] = str(u.boundary.definitions.immutable_location(Path(c[key])))
                controller = load('controller', bridge['controllerScript']).Controller(stage / 'controller', c,
                    runner=lambda *_: (_ for _ in ()).throw(ValueError('Dispatch unavailable during commissioning')))
                controller.close()
                runtime('initialize', stage / 'delivery/delivery.sqlite')
            install_journals(u, state, bridge, initialize)
        if hold.exists():
            empty_journals(h, bridge)
            runtime('verify')
        if running != p['targetSystem'] or hold.exists():
            u.durable(state / 'switch-intent.json', expected)
            if selected != p['targetSystem']:
                u.run([p['nixEnv'], '--profile', '/nix/var/nix/profiles/system', '--set', p['targetSystem']])
            subprocess.run([p['targetSystem'] + '/bin/switch-to-configuration', 'switch'], check=True,
                cwd='/', env={'PATH': '/nonexistent', 'LC_ALL': 'C'}, timeout=300)
        if os.path.realpath('/run/current-system') != p['targetSystem'] or os.path.realpath('/nix/var/nix/profiles/system') != p['targetSystem']:
            raise ValueError('Final host was not selected and activated')
        check_work(h, p)
        u.run([p['systemctl'], 'is-active', *p['requiredUnits']])
        command = [p['runuser'], '-u', 'remote-zettel', '--', p['workCli'], '--socket',
            '/run/remote-zettel/work-control/control.sock', 'board']
        wait_for_work_board(lambda seconds: read_board_command(command, u.ENV, seconds), p['repositories'])
        # Read-only health ties the HTTP revision to systemd's actual MainPID,
        # selected generation and packaged revision. No deployment record is made.
        adapter = load('adapter', p['adapterImplementation']).Adapter(
            json.loads(Path(p['adapterConfiguration']).read_text()),
            vars(load('health_contract', bridge['controllerScript'])))
        health = adapter.health({'generation': p['targetSystem'], 'request': {'commit': p['applicationRevision']}})
        u.durable(state / 'health.json', health)
        u.durable(state / 'release-intent.json', expected)
        if hold.exists():
            if hashlib.sha256(u.install.read_regular(hold, 0, 4096)[0]).hexdigest() != previous['recoveryHoldSha256']:
                raise ValueError('Recovery hold changed before release')
            hold.unlink()
            u.install.sync_dir(hold.parent)
        u.run([p['systemctl'], 'start', 'remote-zettel-deployment-bridge.service'])
        deadline = time.monotonic() + 30
        while True:
            try:
                u.run([p['systemctl'], 'is-active', 'remote-zettel-deployment-bridge.service', 'remote-zettel-deployment-status.service'])
                status = runtime('ready')
                break
            except (ValueError, subprocess.CalledProcessError):
                if time.monotonic() >= deadline:
                    raise ValueError('Deployment readiness failed; inspect the release-intent receipt and live bridge') from None
                time.sleep(0.5)
        u.durable(state / 'complete.json', expected)
        print('AUTOMATIC DEPLOYMENT RESUMED: fresh policy-bound journals and refreshed trusted host.')
        print('Controller policy: ' + status['policyDigest'])
        print('No synthetic release or deployment record was created.')
    finally:
        os.close(lock)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Deployment resume stopped: ' + str(error), file=sys.stderr)
        print('Do not reset journals or change the recovery hold; use the same immutable operator to reconcile.', file=sys.stderr)
        raise SystemExit(1)
