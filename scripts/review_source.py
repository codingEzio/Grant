#!/usr/bin/env python3
"""After human review, update the local source selection's pinned hashes."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

if sys.argv[1:] != ['--reviewed']:
    raise SystemExit('Review the staged selection first; then pass --reviewed.')
root = Path(__file__).resolve().parent.parent

def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

config = json.loads(git('show', ':public-source.json'))
paths = config['files']
if not isinstance(paths, list) or len(paths) != len(set(paths)):
    raise SystemExit('Invalid source selection.')
helper = 'scripts/public_prepare.ts'
sidecar = 'scripts/source-review-hashes.json'
if helper not in paths or sidecar not in paths:
    raise SystemExit('Review helper and pin sidecar must be selected.')
pattern = rb'(const reviewHash =\s*")[a-f0-9]{64}(";)'
pins = {}
for path in sorted(paths):
    if path == sidecar:
        continue
    if not isinstance(path, str) or path.startswith('/') or any(p in ('', '.', '..') for p in path.split('/')):
        raise SystemExit('Invalid selected path.')
    index = git('ls-files', '--stage', '-z', '--', path)
    match = re.fullmatch(rb'(100644|100755) ([a-f0-9]{40,64}) 0\t' + re.escape(path.encode()) + rb'\x00', index)
    if not match:
        raise SystemExit('Selected path must be one regular index entry: ' + path)
    data = git('cat-file', 'blob', match.group(2).decode())
    worktree = root / path
    if worktree.is_symlink() or worktree.resolve() != worktree or worktree.read_bytes() != data:
        raise SystemExit('Working file differs from staged selection: ' + path)
    if path == helper:
        data, count = re.subn(pattern, lambda m: m.group(1) + b'0' * 64 + m.group(2), data)
        if count != 1:
            raise SystemExit('Invalid helper anchor.')
    pins[path] = {'mode': match.group(1).decode(), 'sha256': hashlib.sha256(data).hexdigest()}
encoded = (json.dumps(pins, indent=2, sort_keys=True) + '\n').encode()
helper_path = root / helper
updated, count = re.subn(pattern, lambda m: m.group(1) + hashlib.sha256(encoded).hexdigest().encode() + m.group(2), helper_path.read_bytes())
if count != 1:
    raise SystemExit('Invalid helper anchor.')
(root / sidecar).write_bytes(encoded)
helper_path.write_bytes(updated)
print('Review pin updated; stage the helper and pin sidecar, then run public-check.')
