#!/usr/bin/env python3
"""One-way text-note checkpoints. Never modifies the source tree or rewrites history."""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--remote', required=True)
    parser.add_argument('--local-only', action='store_true', help='Commit locally without requiring network; emit a bounded receipt')
    args = parser.parse_args()
    os.umask(0o077)
    notes = args.notes.resolve(strict=True)
    state = args.state.resolve()
    if not notes.is_dir() or state == notes or notes in state.parents:
        parser.error('state must be outside the notes directory')
    if not (notes / '.gitignore').is_file():
        parser.error('notes .gitignore must exist')
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        repo = state / 'history.git'
        env = dict(os.environ, GIT_TERMINAL_PROMPT='0',
                   GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15',
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null')
        def git(*argv, check=True):
            return subprocess.run(['git', '--literal-pathspecs', '--git-dir', str(repo), '--work-tree', str(notes),
                                   '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgSign=false',
                                   '-c', 'user.name=Zettel checkpoint',
                                   '-c', 'user.email=zettel-checkpoint@localhost', *argv],
                                  env=env, cwd=notes, check=check, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, timeout=90)
        if not repo.exists():
            subprocess.run(['git', 'init', '--bare', '--initial-branch=main', str(repo)],
                           env=env, check=True, capture_output=True)
            git('remote', 'add', 'origin', args.remote)
        if git('remote', 'get-url', 'origin').stdout.strip() != args.remote:
            raise RuntimeError('Remote differs from recorded backup repository; refusing')
        # Defense in depth: a changed .gitignore cannot broaden the upload scope.
        selected = []
        for directory, dirs, files in os.walk(notes, followlinks=False):
            dirs[:] = [d for d in dirs if not d.startswith('.') and not (Path(directory) / d).is_symlink()]
            for name in files:
                path = Path(directory) / name
                relative = path.relative_to(notes)
                allowed = (name == '.gitignore' and relative == Path('.gitignore')) or (
                    not name.startswith('.') and (path.suffix.lower() in {'.md', '.bib'} or
                                                 relative == Path('references/sources.json')))
                if not allowed:
                    continue
                if path.is_symlink():
                    raise RuntimeError('Symlink in selected note files; refusing checkpoint')
                if path.stat().st_size > 10 * 1024 * 1024:
                    raise RuntimeError('Selected text file exceeds 10 MiB; inspect before backing up')
                selected.append(str(relative))
        git('add', '-u')
        for start in range(0, len(selected), 100):
            git('add', '--', *selected[start:start + 100])
        changed = git('diff', '--cached', '--quiet', check=False)
        if changed.returncode not in (0, 1):
            raise RuntimeError('Could not inspect staged checkpoint')
        now = lambda: datetime.now(timezone.utc).isoformat()
        if changed.returncode == 1:
            git('commit', '--quiet', '-m', f'Notes checkpoint {now()}')
        commit = git('rev-parse', 'HEAD').stdout.strip()
        status_path = state / 'status.json'
        status = json.loads(status_path.read_text()) if status_path.exists() else {}
        status.update(local_checkpoint=now(), commit=commit)
        def save():
            temporary = state / 'status.tmp'
            temporary.write_text(json.dumps(status, indent=2) + '\n')
            temporary.replace(status_path)
        save()
        if args.local_only:
            print(json.dumps({'version': 1, 'ok': True, 'root': str(notes), 'commit': commit}))
            return
        # Always retry push, even when there is no new commit. No force, pull or reset.
        pushed = git('push', '--quiet', 'origin', 'HEAD:refs/heads/main', check=False)
        if pushed.returncode:
            status['push_error'] = 'Push failed; local history retained. Check SSH/network/remote divergence.'
            save()
            raise RuntimeError(status['push_error'])
        status.update(last_push=now(), pushed_commit=commit)
        status.pop('push_error', None)
        save()
        print(f'Checkpoint and push complete: {commit}')


if __name__ == '__main__':
    main()
