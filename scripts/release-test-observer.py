"""Bounded app-UID observer. Queries only board, approval history and status."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

p = json.loads(Path(sys.argv[1]).read_text())
p['manifest'] = sys.argv[1]
if os.geteuid() != p['webUid'] or os.geteuid() == 0:
    raise ValueError('Application identity required')
root = Path(p['observerDirectory'])
def call(args):
    return json.loads(subprocess.check_output(args, stdin=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, cwd='/', env={'PATH': '/nonexistent', 'LC_ALL': 'C'}, timeout=20))
def work(args):
    return call([p['workCli'], '--socket', p['controlSocket'], *args])
def write(value):
    temporary = root / ('.status-' + str(uuid.uuid4()))
    fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(root / 'status.json')
deadline = time.monotonic() + 7100
while time.monotonic() < deadline:
    value = {'version': 1, 'taskId': p['taskId'], 'repository': p['repository'],
        'updatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        board = work(['board'])
        task = next((t for t in board['tasks'] if t['id'] == p['taskId']), None)
        runs = [r for r in board.get('runs', []) if r['taskId'] == p['taskId']]
        value['taskStatus'] = task['status'] if task else 'unavailable'
        value['lifecycle'] = task.get('lifecycle', {}).get('state') if task else None
        value['runs'] = [{k: r.get(k) for k in ('id', 'status', 'baseCommit')} for r in runs]
        history = work(['--repository', p['repository'], 'approvals', 'history'])
        value['approvals'] = []
        for entry in history['entries']:
            if entry['taskId'] == p['taskId']:
                value['approvals'].append({k: entry.get(k) for k in ('id', 'eligible', 'runId', 'packageDigest', 'publication')})
        value['deployment'] = call([p['node'], p['statusHelper'], p['manifest']])
        published = [e['publication'] for e in value['approvals'] if e['publication'] and e['publication']['outcome'] == 'published' and e['publication']['slot'] == 'completed']
        deployment = value['deployment']
        value['testSucceeded'] = any(deployment['state'] == 'succeeded' and deployment['error'] is None
            and deployment['runningRevision'] == deployment['desiredRevision'] == deployment['publishedRevision'] == pub['candidateCommit']
            for pub in published)
    except Exception:
        value['observerError'] = 'read-only projection unavailable; no mutations were retried'
    write(value)
    if value.get('testSucceeded'):
        break
    time.sleep(3)
