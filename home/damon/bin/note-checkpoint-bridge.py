#!/usr/bin/env python3
"""Linux peer-UID-authenticated local-only note checkpoint service."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pwd
import re
import signal
import socket
import stat
import struct
import subprocess
import sys
import time


def checkpoint(args):
    process = subprocess.Popen([sys.executable, str(args.checkpoint), '--notes', str(args.notes),
        '--state', str(args.state), '--remote', args.remote, '--local-only'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise ValueError('Checkpoint timed out')
    if process.returncode or len(output) > 4096:
        raise ValueError('Checkpoint failed')
    receipt = json.loads(output)
    if (not isinstance(receipt, dict) or receipt.get('version') != 1 or receipt.get('ok') is not True
            or receipt.get('root') != str(args.notes) or not isinstance(receipt.get('commit'), str)
            or not re.fullmatch(r'(?:[a-f0-9]{40}|[a-f0-9]{64})', receipt['commit'])):
        raise ValueError('Invalid checkpoint receipt')
    return {key: receipt[key] for key in ('version', 'ok', 'root', 'commit')}


def handle(peer, args):
    _, uid, _ = struct.unpack('3i', peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid != args.allowed_uid:
        return
    deadline = time.monotonic() + 3
    data = b''
    while b'\n' not in data:
        peer.settimeout(max(.001, deadline - time.monotonic()))
        chunk = peer.recv(1025 - len(data))
        if not chunk:
            return
        data += chunk
        if len(data) > 1024 or time.monotonic() >= deadline:
            return
    request = json.loads(data)
    if request != {'version': 1, 'op': 'checkpoint'} or type(request.get('version')) is not int:
        return
    try:
        response = checkpoint(args)
    except (ValueError, OSError, subprocess.SubprocessError):
        response = {'version': 1, 'ok': False, 'error': 'Local checkpoint failed'}
    peer.settimeout(3)
    peer.sendall((json.dumps(response) + '\n').encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True)
    who = parser.add_mutually_exclusive_group(required=True)
    who.add_argument('--allowed-uid', type=int)
    who.add_argument('--allowed-user')
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--remote', required=True)
    parser.add_argument('--checkpoint', type=Path, required=True)
    args = parser.parse_args()
    if args.allowed_user:
        args.allowed_uid = pwd.getpwnam(args.allowed_user).pw_uid
    args.notes = args.notes.resolve(strict=True)
    os.umask(0o077)
    directory = args.socket.parent.lstat()
    if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.getuid() or directory.st_mode & 0o022:
        raise ValueError('Socket directory must be owned by the service and not group/other writable')
    fd = os.open(args.socket.parent / '.owner.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            existing = args.socket.lstat()
        except FileNotFoundError:
            existing = None
        if existing:
            if not stat.S_ISSOCK(existing.st_mode) or existing.st_uid != os.getuid():
                raise ValueError('Refusing to replace unexpected socket path')
            args.socket.unlink()
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(args.socket))
            os.chmod(args.socket, 0o660)
            listener.listen(4)
            # Deliberately serial: bounded memory/process count; timed-out clients fail closed.
            while True:
                peer, _ = listener.accept()
                with peer:
                    try:
                        handle(peer, args)
                    except (OSError, ValueError, UnicodeError):
                        pass  # Never echo request data or subprocess diagnostics.


if __name__ == '__main__':
    main()
