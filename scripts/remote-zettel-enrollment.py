#!/usr/bin/env python3
"""Root operator workflow. Immutable Nix plan; no authority resets or publication."""
import fcntl
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys
import tempfile
import time

PHASES = ('source-ready', 'prepared', 'authenticated', 'active')


def run(*command, capture=False):
    result = subprocess.run([str(arg) for arg in command], check=True, text=True, cwd='/',
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def protected_json(path):
    path = Path(path)
    for parent in path.parents:
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise RuntimeError(f'Unprotected state ancestor: {parent}')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_gid != 0
                or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
            raise RuntimeError(f'Unsafe operator state: {path}')
        data = os.read(fd, 65537)
        if len(data) > 65536:
            raise RuntimeError('Operator state exceeds budget')
        return json.loads(data)
    finally:
        os.close(fd)


def operator_directory(plan):
    directory = Path(plan['operatorState'])
    for parent in directory.parents:
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise RuntimeError(f'Unprotected operator ancestor: {parent}')
    if not directory.exists():
        directory.mkdir(mode=0o700)
    info = directory.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_gid != 0
            or stat.S_IMODE(info.st_mode) != 0o700):
        raise RuntimeError('Unsafe operator state directory')
    return directory


def save_phase(plan, phase):
    directory = operator_directory(plan)
    value = {'version': 1, 'policyDigest': plan['policyDigest'], 'phase': phase}
    fd, temporary = tempfile.mkstemp(prefix='.phase-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(value, output, sort_keys=True)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, directory / 'state.json')
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def credentials_present(plan):
    path = Path(plan['credentials'])
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != plan['hostUid']
            or info.st_gid != plan['hostGid'] or info.st_nlink != 1
            or info.st_mode & 0o077):
        raise RuntimeError('Credential metadata is unsafe; no credential was changed')
    return True


def switch(plan, target):
    target = str(Path(target).resolve(strict=True))
    current = str(Path(plan['currentSystem']).resolve(strict=True))
    selected = str(Path(plan['systemProfile']).resolve(strict=True))
    if current != target or selected != target:
        print(f'Activating {target}', flush=True)
        run(plan['nixEnv'], '-p', plan['systemProfile'], '--set', target)
        try:
            run(str(Path(target) / 'bin/switch-to-configuration'), 'switch')
        except subprocess.CalledProcessError:
            print('Activation failed; stopped before login/readiness commands. '
                  f'Selected profile: {Path(plan["systemProfile"]).resolve()}; '
                  f'running system: {Path(plan["currentSystem"]).resolve()}. '
                  'Keep the error above; no rollback or state reset was attempted.', file=sys.stderr)
            raise
    if (Path(plan['currentSystem']).resolve(strict=True) != Path(target)
            or Path(plan['systemProfile']).resolve(strict=True) != Path(target)):
        raise RuntimeError('The selected profile and running system do not match the target')


def enroll(plan):
    journal = Path(plan['operatorState']) / 'state.json'
    phase = None
    if os.path.lexists(journal):
        value = protected_json(journal)
        if (set(value) != {'version', 'policyDigest', 'phase'} or value['version'] != 1
                or value['policyDigest'] != plan['policyDigest'] or value['phase'] not in PHASES):
            raise RuntimeError('Operator policy changed; an explicit policy transition is required')
        phase = value['phase']
    marker = Path(plan['policyMarker'])
    reserved = os.path.lexists(marker)
    prepared = False
    if reserved:
        value = protected_json(marker)
        expected = json.loads(Path(plan['stateConfiguration']).read_text())
        if (set(value) != {'configuration', 'phase'} or value['configuration'] != expected
                or value['phase'] not in ('preparing', 'prepared')):
            raise RuntimeError('Existing instance reservation differs from this configuration')
        prepared = value['phase'] == 'prepared'
        if not prepared and phase in ('prepared', 'authenticated', 'active'):
            raise RuntimeError('A completed instance reservation is now incomplete')
        if prepared:
            run(plan['guard'], 'verify')
    elif phase in ('prepared', 'authenticated', 'active'):
        raise RuntimeError('Prepared instance state is missing; it will not be recreated')

    present = credentials_present(plan)
    if present and not prepared:
        raise RuntimeError('Credentials have no completed matching instance reservation')
    authenticated = False
    if present:
        host_running = subprocess.run([plan['systemctl'], 'is-active', '--quiet', plan['hostUnit']],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd='/').returncode == 0
        if host_running:
            authenticated = True
        else:
            result = subprocess.run([plan['runuser'], '-u', plan['hostUser'], '--', plan['authProbe']], cwd='/')
            if result.returncode not in (0, 3):
                raise RuntimeError('Existing authentication could not be verified; nothing was replaced')
            authenticated = result.returncode == 0
    if not authenticated and (phase in ('authenticated', 'active') or os.path.lexists(plan['hostLedger'])):
        raise RuntimeError('Previously installed credentials are missing; no automatic replacement')
    if not authenticated and not (sys.stdin.isatty() and sys.stdout.isatty()):
        raise RuntimeError('Dedicated login needs an interactive terminal; rerun this command there')

    source_paths = [Path(path) for path in plan['sourceRoots']]
    if any(os.path.lexists(path) for path in source_paths):
        run(plan['commissionSource'], '--verify')
    else:
        if phase is not None or reserved:
            raise RuntimeError('Previously enrolled source is missing; it will not be recreated')
        run(plan['commissionSource'], '--commission')
        run(plan['commissionSource'], '--verify')
    if phase is None:
        save_phase(plan, 'source-ready')

    if not authenticated:
        switch(plan, plan['preparedSystem'])
        run(plan['systemctl'], 'start', plan['prepareUnit'])
        run(plan['systemctl'], 'is-active', plan['prepareUnit'])
        run(plan['guard'], 'verify')
        save_phase(plan, 'prepared')
        print('Complete the dedicated login in this terminal.', flush=True)
        run(plan['login'])
        if not credentials_present(plan):
            raise RuntimeError('Login did not install the expected private credential file')
        run(plan['runuser'], '-u', plan['hostUser'], '--', plan['authProbe'])
        save_phase(plan, 'authenticated')
    if authenticated and phase != 'active':
        save_phase(plan, 'authenticated')
    switch(plan, plan['executionSystem'])
    run(plan['systemctl'], 'start', *plan['units'])
    run(plan['systemctl'], 'is-active', *plan['units'])
    prefix = [plan['runuser'], '-u', plan['webUser'], '--', plan['workCli'],
              '--socket', plan['controlSocket']]
    deadline = time.monotonic() + 30
    while True:
        try:
            board = json.loads(run(*prefix, 'board', capture=True))
            catalog = json.loads(run(*prefix, 'repositories', 'catalog', capture=True))
            if plan['repository'] not in board['repositories']:
                raise RuntimeError('The repository is absent from the live Work board')
            if not any(item['repository'] == plan['repository'] for item in catalog):
                raise RuntimeError('The repository reader is absent from the live catalog')
            break
        except (subprocess.CalledProcessError, ValueError, KeyError, RuntimeError) as error:
            if time.monotonic() >= deadline:
                detail = getattr(error, 'stderr', None) or str(error)
                raise RuntimeError(f'Work readiness did not settle within 30 seconds: {detail}') from error
            time.sleep(0.5)  # Only retry read-only board/catalog observations.
    save_phase(plan, 'active')
    print(f'Enrollment active and verified: {plan["repository"]}. '
          'Publication and deployment are not commissioned.')


def main():
    if os.geteuid() != 0:
        raise RuntimeError('Run the repository launcher; it requests sudo after building')
    if len(sys.argv) != 2:
        raise RuntimeError('Expected the immutable Nix enrollment plan')
    plan = json.loads(Path(sys.argv[1]).read_text())
    if socket.gethostname() != plan['hostname']:
        raise RuntimeError(f'This enrollment is for {plan["hostname"]}')
    directory = operator_directory(plan)
    fd = os.open(directory / 'operator.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_gid != 0
                or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
            raise RuntimeError('Unsafe operator lock')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another enrollment operation is running') from None
        enroll(plan)
    finally:
        os.close(fd)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('Enrollment interrupted; retained state can be resumed with the same repository command.', file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f'Enrollment stopped: {error}', file=sys.stderr)
        sys.exit(1)
