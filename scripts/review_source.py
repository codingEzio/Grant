#!/usr/bin/env python3
"""After human review, update the local source selection's pinned hashes."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


def checked_file(path):
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or path.resolve() != path:
        raise ValueError('Output must be a regular file without symlink ancestors.')
    return info


def read_checked(path, expected):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or not same_file(info, expected):
            raise ValueError('Reviewed file changed while reading.')
        with os.fdopen(fd, 'rb', closefd=False) as source:
            return source.read()
    finally:
        os.close(fd)


def swap(source, destination):
    # Atomic exchange keeps the displaced entry available for identity checks.
    lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    fn = lib.renamex_np
    fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    fn.restype = ctypes.c_int
    if fn(os.fsencode(source), os.fsencode(destination), 2) != 0:  # RENAME_SWAP
        number = ctypes.get_errno()
        raise OSError(number, os.strerror(number))


def same_file(left, right):
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)


def atomic_replace(path, content, expected=None, expected_content=None):
    """Exchange a same-directory temporary file; reject a changed destination."""
    original = checked_file(path)
    if expected is not None and not same_file(original, expected):
        raise ValueError("Output changed after review.")
    original_content = read_checked(path, original)
    if expected_content is not None and original_content != expected_content:
        raise ValueError("Output contents changed after review.")
    fd, name = tempfile.mkstemp(prefix='.grant-review-', dir=path.parent)
    temporary = Path(name)
    staged = None
    exchanged = False
    keep = False
    try:
        with os.fdopen(fd, 'wb') as output:
            os.fchmod(output.fileno(), stat.S_IMODE(original.st_mode))
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
            staged = os.fstat(output.fileno())
        current = checked_file(path)
        if not same_file(current, original):
            raise ValueError('Output changed while preparing update.')
        swap(temporary, path)
        exchanged = True
        displaced = os.lstat(temporary)
        new = os.lstat(path)
        try:
            displaced_matches = (stat.S_ISREG(displaced.st_mode) and same_file(displaced, original)
                                 and read_checked(temporary, displaced) == original_content)
        except (OSError, ValueError):
            displaced_matches = False
        if not displaced_matches or not same_file(new, staged):
            # Roll back only while our new file still occupies the destination.
            if same_file(new, staged):
                swap(temporary, path)
                exchanged = False
            else:
                keep = True
            raise ValueError('Output changed during update; displaced entry retained if needed.')
        os.unlink(temporary)
        exchanged = False
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        # Never remove a displaced entry after an incomplete exchange.
        if not exchanged and not keep:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def main():
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
    outputs = {}
    for output in (sidecar, helper):
        index = git('ls-files', '--stage', '-z', '--', output)
        if not re.fullmatch(rb'(100644|100755) [a-f0-9]{40,64} 0\t' + re.escape(output.encode()) + rb'\x00', index):
            raise SystemExit('Review output must be a regular index entry.')
        outputs[output] = checked_file(root / output)
    pattern = rb'(const reviewHash =\s*")[a-f0-9]{64}(";)'
    pins = {}
    helper_original = None
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
        observed = checked_file(worktree)
        if read_checked(worktree, observed) != data:
            raise SystemExit('Working file differs from staged selection: ' + path)
        if path == helper:
            if not same_file(observed, outputs[helper]):
                raise ValueError("Helper changed after review.")
            helper_original = data
            data, count = re.subn(pattern, lambda m: m.group(1) + b'0' * 64 + m.group(2), data)
            if count != 1:
                raise SystemExit('Invalid helper anchor.')
        pins[path] = {'mode': match.group(1).decode(), 'sha256': hashlib.sha256(data).hexdigest()}
    encoded = (json.dumps(pins, indent=2, sort_keys=True) + '\n').encode()
    helper_path = root / helper
    updated, count = re.subn(pattern, lambda m: m.group(1) + hashlib.sha256(encoded).hexdigest().encode() + m.group(2), helper_original)
    if count != 1:
        raise SystemExit('Invalid helper anchor.')
    # If the second update fails, the mismatched pin is rejected until a rerun.
    atomic_replace(root / sidecar, encoded, outputs[sidecar])
    atomic_replace(helper_path, updated, outputs[helper], helper_original)
    print('Review pin updated; stage the helper and pin sidecar, then run public-check.')


if __name__ == '__main__':
    main()
