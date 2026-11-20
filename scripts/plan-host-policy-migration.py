#!/usr/bin/env python3
"""Capture public immutable migration inputs. Does not authorize or migrate state."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def immutable(path):
    path = Path(path).resolve(strict=True)
    if not re.fullmatch(r'/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/]+(?:/.*)?', str(path)):
        raise ValueError('Expected immutable generation input: ' + str(path))
    return path


def read(path):
    path = immutable(path)
    raw = path.read_bytes()
    if len(raw) > 1024 * 1024:
        raise ValueError('Migration metadata budget exceeded')
    return json.loads(raw)


def system(path):
    root = Path(path).resolve(strict=True)
    if not re.fullmatch(r'/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-nixos-system-deeley-[A-Za-z0-9+._=-]+', str(root)):
        raise ValueError('Expected an immutable Deeley system')
    return root


def command(unit, key):
    lines = [line.removeprefix(key + '=') for line in immutable(unit).read_text().splitlines()
             if line.startswith(key + '=')]
    if len(lines) != 1:
        raise ValueError('Expected one ' + key + ' in ' + str(unit))
    return shlex.split(lines[0].removeprefix('+'))


def snapshot(root):
    generation = read(root / 'etc/remote-zettel-work-generation.json')
    upgrade = read(root / 'etc/remote-zettel-work-upgrade.json')
    bridge = read(root / 'etc/remote-zettel-self-deployment/bridge.json')
    instances = {}
    unit_root = root / 'etc/systemd/system'
    for host in sorted(unit_root.glob('remote-zettel-work-instance-*-host.service')):
        prefix = host.name.removesuffix('-host.service')
        invocation = command(host, 'ExecStart')
        if len(invocation) != 4 or invocation[2] != 'serve':
            raise ValueError('Unexpected host invocation')
        enrollment = read(invocation[3])
        guard = command(host, 'ExecStartPre')
        if len(guard) != 2 or guard[1] != 'verify':
            raise ValueError('Unexpected instance guard')
        script = immutable(guard[0]).read_text()
        matches = re.findall(r'--configuration (/nix/store/[^\s"\']+)', script)
        if len(matches) != 1:
            raise ValueError('Unexpected instance state configuration')
        instances[prefix] = dict(enrollment=enrollment, state=read(matches[0]))
    units = {}
    for unit in sorted(unit_root.glob('remote-zettel*')):
        if unit.name.endswith(('.service', '.socket', '.slice')):
            units[unit.name] = hashlib.sha256(immutable(unit).read_bytes()).hexdigest()
    return dict(generation=generation, upgrade=upgrade,
        storiesEnrollment=read(upgrade['enrollment']), instances=instances, bridge=bridge,
        controller=read(bridge['controllerConfigurationFile']), units=units)


def changes(before, after, prefix=''):
    if isinstance(before, dict) and isinstance(after, dict):
        result = []
        for key in sorted(before.keys() | after.keys()):
            path = prefix + '/' + key
            if key not in before or key not in after:
                result.append(path)
            else:
                result.extend(changes(before[key], after[key], path))
        return result
    return [] if before == after else [prefix]


def check_enrollment(before, after):
    a, b = dict(before), dict(after)
    profile_a, profile_b = dict(a.pop('profile')), dict(b.pop('profile'))
    for profile in (profile_a, profile_b):
        for key in ('checkCommand', 'candidateCheckProfile', 'candidateReviewProfile'):
            profile.pop(key, None)
    if a != b or profile_a != profile_b:
        raise ValueError('Unexpected enrollment change outside check/review toolchain')


def plan(old, new):
    before, after = snapshot(old), snapshot(new)
    if before['instances'].keys() != after['instances'].keys():
        raise ValueError('Repository instance additions/removals need a separate transition')
    for key in ('repository', 'identities', 'shared'):
        if before['generation'][key] != after['generation'][key]:
            raise ValueError('Unexpected generation identity/path change: ' + key)
    check_enrollment(before['storiesEnrollment'], after['storiesEnrollment'])
    for name in before['instances']:
        a, b = before['instances'][name], after['instances'][name]
        for key in ('directories', 'policyDirectory', 'sourceRepository'):
            if a['state'][key] != b['state'][key]:
                raise ValueError('Unexpected software identity/path change: ' + key)
        check_enrollment(a['enrollment'], b['enrollment'])
    for key in ('target', 'repository', 'commandTimeoutSeconds'):
        if before['controller'][key] != after['controller'][key]:
            raise ValueError('Unexpected deployment controller identity/budget change')
    result = dict(version=1, role='host-policy-migration-plan', sourceSystem=str(old), targetSystem=str(new),
        sourceDigest=digest(before), targetDigest=digest(after), changes=changes(before, after),
        before=before, after=after,
        prerequisites=['reconcile-profile-and-boot', 'protected-live-state-inspection',
                       'drain-both-work-instances-and-publication', 'verified-consistent-backup',
                       'explicit-policy-migration-receipts', 'refresh-captured-deployment-host',
                       'production-service-vm-rehearsal'],
        activationAuthorized=False)
    return dict(result, planDigest=digest(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target')
    parser.add_argument('--current', default='/run/current-system')
    args = parser.parse_args()
    print(json.dumps(plan(system(args.current), system(args.target)), sort_keys=True, indent=2))
