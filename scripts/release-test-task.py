"""Create exactly the reviewed task document as the application UID, never root."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import uuid

p = json.loads(Path(sys.argv[1]).read_text())
if os.geteuid() != p['webUid'] or os.geteuid() == 0:
    raise ValueError('Application identity required')
root = Path(p['documentsRoot']) / 'tasks'
if root.resolve(strict=True) != root:
    raise ValueError('Task directory was redirected')
destination = root / (str(uuid.UUID(p['taskId'])) + '.md')
raw = Path(p['taskDocument']).read_bytes()
if hashlib.sha256(raw).hexdigest() != p['taskRevision']:
    raise ValueError('Reviewed task document changed')
if os.path.lexists(destination):
    info = destination.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or destination.read_bytes() != raw:
        raise ValueError('Existing task differs; no overwrite permitted')
else:
    temporary = root / ('.release-test-' + str(uuid.uuid4()) + '.tmp')
    fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, destination, follow_symlinks=False)
    finally:
        temporary.unlink()
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
