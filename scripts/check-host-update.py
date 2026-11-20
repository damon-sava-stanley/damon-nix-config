#!/usr/bin/env python3
"""Read-only early diagnostics, supplementary to privileged activation checks."""
import json
from pathlib import Path
import sys


def read_json(path):
    return json.loads(path.read_text())


def check(current, target):
    errors = []
    relative = 'etc/remote-zettel-work-generation.json'
    old_path, new_path = current / relative, target / relative
    if old_path.exists():
        old = read_json(old_path)
        if not new_path.exists():
            errors.append('Target removes the enrolled Work generation contract.')
        else:
            new = read_json(new_path)
            if old['epoch'] == new['epoch'] and old['bundle'] != new['bundle']:
                errors.append(
                    f"Work epoch {old['epoch']} has a different writer/toolchain bundle.\n"
                    f"  enrolled: {old['bundle']}\n  target:   {new['bundle']}\n"
                    'A nixpkgs update can cause this even when the Work source pin is unchanged.\n'
                    'An explicit Work policy migration is required; this is not an inactive installation.')
            if old['epoch'] != new['epoch'] and new.get('retired', {}) != {
                    **old.get('retired', {}), old['epoch']: old['bundle']}:
                errors.append('Target is not a declared successor retaining the current Work epoch.\n'
                              'Use the supported transition/recovery operator; ordinary install cannot select a retired policy.')

    relative = 'etc/remote-zettel-host-software-transition.json'
    old_path, new_path = current / relative, target / relative
    if new_path.exists() and (not old_path.exists() or read_json(old_path) != read_json(new_path)):
        errors.append('A two-repository policy transition requires its prepared host migration operator.\n'
                      'Run that operator to snapshot, provision and switch; ordinary install cannot prepare it.')
    if old_path.exists() and not new_path.exists():
        errors.append('Target removes the enrolled software transition contract.')

    relative = 'etc/remote-zettel-self-deployment/bridge.json'
    old_path, new_path = current / relative, target / relative
    if old_path.exists() and new_path.exists():
        old, new = read_json(old_path), read_json(new_path)
        if (old['controllerStateDirectory'] == new['controllerStateDirectory']
                and read_json(Path(old['controllerConfigurationFile']))
                != read_json(Path(new['controllerConfigurationFile']))):
            errors.append('The deployment controller policy changed while retaining its journal.\n'
                          'Controller journal policy migration is not implemented; changing pins is insufficient.')
    return errors


def main():
    if len(sys.argv) != 2:
        raise ValueError('Usage: check-host-update.py TARGET_SYSTEM')
    current = Path('/run/current-system').resolve(strict=True)
    selected = Path('/nix/var/nix/profiles/system').resolve(strict=True)
    target = Path(sys.argv[1]).resolve(strict=True)
    if selected != current:
        print(f'Warning: running system and selected system profile differ.\n'
              f'  running:  {current}\n  selected: {selected}\n'
              'Inspect the previous switch failure before rebooting.', file=sys.stderr)
    errors = check(current, target)
    if errors:
        print('Host update refused before sudo or profile selection:\n\n' + '\n\n'.join(errors), file=sys.stderr)
        print('\nSee deployments/host-update-migration.md. No state was migrated.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Host update preflight failed: {error}', file=sys.stderr)
        sys.exit(1)
