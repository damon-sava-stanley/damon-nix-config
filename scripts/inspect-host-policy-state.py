#!/usr/bin/env python3
"""Bounded read-only policy-state inventory. No credentials, owners or lifecycle calls."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys

SOURCE = '/nix/store/jczv8zybgjkdaag30kc7fv1bg6gaig28-nixos-system-deeley-26.05.20261113.f1e5c35'
spec = importlib.util.spec_from_file_location('planner', Path(__file__).with_name('plan-host-policy-migration.py'))
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)

# Fixed table and status names only. Never read task text, evidence, session data,
# credential tables, SQL supplied by a database, or arbitrary file content.
GROUPS = {'work_runs': 'status', 'work_preparation_attempts': 'state', 'work_task_closeout': 'cleanup',
          'sequential_runs': 'status', 'runs': 'phase', 'cleanup_requests': 'state',
          'checks': 'phase', 'reviews': 'phase', 'attempts': 'state'}
COUNTS = {'work_tasks', 'work_publication_reservations', 'work_publication_outbox',
          'work_publication_completions', 'work_preparation_attempts', 'work_approval_packages',
          'workspaces', 'candidate_profiles', 'review_profiles', 'publication_owner_reservation',
          'publication_owner_retirements', 'publication_owner_outcomes', 'deployments', 'deployment_delivery'}


def safe_file(path):
    if path.resolve(strict=True) != path:
        raise ValueError('Symlinked inventory input')
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_mode & 0o002:
        raise ValueError('Unsafe inventory file')
    return info


def inventory_database(path):
    safe_file(path)
    result = dict(path=str(path), counts={}, states={})
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=0)
    try:
        db.execute('PRAGMA trusted_schema=OFF')
        db.execute('PRAGMA query_only=ON')
        db.execute('BEGIN')
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        result['tables'] = sorted(tables)
        for table in sorted(tables & COUNTS):
            result['counts'][table] = db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
        for table in sorted(tables & GROUPS.keys()):
            column = GROUPS[table]
            columns = {row[1] for row in db.execute(f'PRAGMA table_info("{table}")')}
            if column not in columns:
                result['states'][table] = {'unsupported-schema': True}
                continue
            rows = db.execute(f'SELECT "{column}", COUNT(*) FROM "{table}" GROUP BY "{column}" LIMIT 65').fetchall()
            if len(rows) > 64 or any(value is not None and (not isinstance(value, str)
                    or not re.fullmatch('[a-z0-9-]{1,64}', value)) for value, _ in rows):
                raise ValueError('Unsupported status inventory')
            result['states'][table] = {value or '<null>': count for value, count in rows}
        if 'work_publication_outbox' in tables and 'work_publication_completions' in tables:
            result['uncompletedPublicationSlots'] = db.execute('SELECT COUNT(*) FROM work_publication_outbox o '
                'LEFT JOIN work_publication_completions c ON c.id=o.id WHERE c.id IS NULL').fetchone()[0]
        if 'deployment_delivery' in tables:
            result['unacknowledgedDeliveries'] = db.execute('SELECT COUNT(*) FROM deployment_delivery WHERE acknowledgment IS NULL').fetchone()[0]
        return result
    finally:
        db.close()


def collect_databases(root, names):
    if root.resolve(strict=True) != root or not root.is_dir():
        raise ValueError('Unsafe ledger root')
    selected = []
    # Never traverse checkouts, package dependencies, artifacts or session trees.
    for parent in [root] + [root / name for name in
            ('operations', 'captures', 'validations', 'candidate-ledger', 'review-ledger')]:
        if not parent.exists():
            continue
        if parent.resolve(strict=True) != parent or not parent.is_dir():
            raise ValueError('Symlinked ledger directory')
        for name in sorted(names):
            path = parent / name
            if path.exists() or path.is_symlink():
                selected.append(path)
    return sorted(selected)


def inspect():
    if str(Path('/run/current-system').resolve(strict=True)) != SOURCE:
        raise ValueError('Running generation changed')
    s = planner.snapshot(Path(SOURCE))
    u = s['upgrade']
    selections = dict(running=SOURCE, selected=str(Path('/nix/var/nix/profiles/system').resolve(strict=True)))
    if selections['running'] != selections['selected']:
        raise ValueError('Profile reconciliation is incomplete')
    result = dict(version=1, role='host-policy-state-inventory', selections=selections,
                  observationOnly=True, databases=[], publicationConfigurations={}, receipts={})
    paths = [Path(u['coordinatorStatePath']), Path(u['hostRoot']) / 'admission.sqlite', Path(u['publisherStorePath'])]
    executor_roots = [Path('/var/lib') / Path(s['storiesEnrollment']['profile']['supervisorSocket']).parent.name]
    ingestion_roots = [Path(u['ingestionDirectory'])]
    for instance in s['instances'].values():
        e = instance['enrollment']
        paths.extend([Path(e['profile']['statePath'])])
        # The coordinator path is a generated instance default in this enrollment.
        paths.append(Path('/var/lib/remote-zettel/work/remote-zettel/state.sqlite'))
        executor_roots.append(Path('/var/lib') / Path(e['profile']['supervisorSocket']).parent.name)
    for root in executor_roots:
        paths.extend(collect_databases(root, {'runs.sqlite', 'checks.sqlite', 'reviews.sqlite'}))
    software_root = Path('/var/lib/remote-zettel-software-publication')
    paths.append(software_root / 'publisher/state.sqlite')
    ingestion_roots.append(software_root / 'ingestion')
    for root in ingestion_roots:
        paths.extend(sorted(path for path in root.glob('*.sqlite') if not path.name.endswith('.ownership.sqlite')))
    bridge = s['bridge']
    paths.extend([Path(bridge['controllerStateDirectory']) / 'state.sqlite', Path(bridge['deliveryStatePath'])])
    if len(paths) > 48:
        raise ValueError('Database inventory budget exceeded')
    for path in dict.fromkeys(paths):
        try:
            result['databases'].append(inventory_database(path))
        except (OSError, ValueError, sqlite3.Error) as error:
            result['databases'].append(dict(path=str(path), unavailable=type(error).__name__))
    for name, path in [('stories', Path(u['publisherConfigurationFile'])),
                       ('software', software_root / 'config/operator.json')]:
        safe_file(path)
        if path.stat().st_size > 65536:
            raise ValueError('Publication metadata budget exceeded')
        config = json.loads(path.read_text())
        # Explicit policy allowlist; never dump entire protected configurations.
        result['publicationConfigurations'][name] = {key: config[key] for key in
            ('outcomePolicy', 'ownerPolicy') if key in config}
    for name in ['reconcile-before.json', 'reconcile-complete.json']:
        path = Path('/var/lib/remote-zettel-host-maintenance') / name
        safe_file(path)
        result['receipts'][name] = json.loads(path.read_text())
    hold = Path(bridge['controllerStateDirectory']) / 'operator-recovery'
    safe_file(hold)
    result['deploymentHoldSha256'] = hashlib.sha256(hold.read_bytes()).hexdigest()
    return result


if __name__ == '__main__':
    if os.geteuid() != 0 or not sys.flags.isolated or len(sys.argv) != 1:
        raise SystemExit('Isolated root invocation with no arguments required')
    print(json.dumps(inspect(), sort_keys=True, indent=2))
