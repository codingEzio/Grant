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
import secrets


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


def same_file(left, right):
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)


def rename_exclusive(directory_fd, source, destination):
    lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    fn = lib.renameatx_np
    fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    fn.restype = ctypes.c_int
    if fn(directory_fd, os.fsencode(source), directory_fd, os.fsencode(destination), 4) != 0:
        number = ctypes.get_errno()
        raise OSError(number, os.strerror(number))


def stat_at(directory_fd, name):
    info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode):
        raise ValueError('Review output must be a regular file.')
    return info


def read_at(directory_fd, name, expected):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or not same_file(info, expected):
            raise ValueError('Review output changed while reading.')
        with os.fdopen(fd, 'rb', closefd=False) as source:
            return source.read()
    finally:
        os.close(fd)


def guard_directory(directory_fd, parent_path):
    info = os.lstat(parent_path)
    if not stat.S_ISDIR(info.st_mode) or not same_file(info, os.fstat(directory_fd)):
        raise ValueError('Scripts directory changed; retained files are in the original directory.')


def atomic_replace(directory_fd, parent_path, name, content, expected=None, expected_content=None):
    """Publish without overwriting; retain previous and uncertain entries."""
    if '/' in name or name in ('', '.', '..'):
        raise ValueError('Invalid review output name.')
    original = stat_at(directory_fd, name)
    if expected is not None and not same_file(original, expected):
        raise ValueError('Output changed after review.')
    original_content = read_at(directory_fd, name, original)
    if expected_content is not None and original_content != expected_content:
        raise ValueError('Output contents changed after review.')
    token = secrets.token_hex(16)
    temporary = f'.grant-review-new-{token}'
    retained = f'.grant-review-previous-{token}'
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
    try:
        with os.fdopen(fd, 'wb') as output:
            os.fchmod(output.fileno(), stat.S_IMODE(original.st_mode))
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
            staged = os.fstat(output.fileno())
        current = stat_at(directory_fd, name)
        if not same_file(current, original) or read_at(directory_fd, name, current) != original_content:
            raise ValueError('Output changed while preparing update.')
        # A crash at either boundary leaves every entry in the pinned directory.
        guard_directory(directory_fd, parent_path)
        rename_exclusive(directory_fd, name, retained)
        guard_directory(directory_fd, parent_path)
        displaced = stat_at(directory_fd, retained)
        if not same_file(displaced, original) or read_at(directory_fd, retained, displaced) != original_content:
            raise ValueError('Output changed during preservation.')
        if not same_file(stat_at(directory_fd, temporary), staged) or read_at(directory_fd, temporary, staged) != content:
            raise ValueError('Prepared output changed.')
        guard_directory(directory_fd, parent_path)
        rename_exclusive(directory_fd, temporary, name)
        guard_directory(directory_fd, parent_path)
        current = stat_at(directory_fd, name)
        if not same_file(current, staged) or read_at(directory_fd, name, current) != content:
            raise ValueError('Published output changed.')
        os.fsync(directory_fd)
        return retained
    except BaseException:
        print(f'Review update interrupted; inspect pinned scripts directory entries {name}, {temporary}, {retained}; no entry was overwritten or deleted.', file=sys.stderr)
        raise


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
    scripts_fd = os.open(root / 'scripts', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    parent_info = os.lstat(root / 'scripts')
    if not stat.S_ISDIR(parent_info.st_mode) or not same_file(parent_info, os.fstat(scripts_fd)):
        raise SystemExit('Scripts directory changed; no output updated.')
    outputs = {}
    for output in (sidecar, helper):
        index = git('ls-files', '--stage', '-z', '--', output)
        if not re.fullmatch(rb'(100644|100755) [a-f0-9]{40,64} 0\t' + re.escape(output.encode()) + rb'\x00', index):
            raise SystemExit('Review output must be a regular index entry.')
        outputs[output] = stat_at(scripts_fd, Path(output).name)
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
    first = atomic_replace(scripts_fd, root / "scripts", Path(sidecar).name, encoded, outputs[sidecar])
    second = atomic_replace(scripts_fd, root / "scripts", Path(helper).name, updated, outputs[helper], helper_original)
    os.close(scripts_fd)
    print(f'Review pin updated; previous files retained in scripts/{first} and scripts/{second}. Stage helper and sidecar, then run public-check.')


if __name__ == '__main__':
    main()
