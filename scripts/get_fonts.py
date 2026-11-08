#!/usr/bin/env python3
"""Obtain hash-pinned font build inputs without replacing existing files."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import urllib.request
import zipfile
import get_compact_font

ROOT = Path(__file__).resolve().parent.parent

def verify(path, asset):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as file:
            info = os.fstat(file.fileno())
            data = file.read(asset['bytes'] + 1) if stat.S_ISREG(info.st_mode) else b''
        if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
            raise ValueError('existing font mismatch')
    except FileNotFoundError:
        raise ValueError('font missing')

def main():
    if sys.argv[1:] not in ([], ['--check']):
        raise ValueError('usage: python3 scripts/get_fonts.py [--check]')
    assets = json.loads((ROOT / 'Resources/Licenses/fonts.json').read_text())['assets']
    for asset in assets:
        if not asset['path'].startswith('Resources/Fonts/') or 'archiveMember' in asset:
            continue
        path = ROOT / asset['path']
        if os.path.lexists(path) or sys.argv[1:]:
            verify(path, asset)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(asset['sourceURL'], headers={'User-Agent': 'Grant-source-setup'})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read(asset['bytes'] + 1)
        if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
            raise ValueError('downloaded font mismatch')
        fd, tmp = tempfile.mkstemp(prefix='.font-', dir=path.parent)
        try:
            with os.fdopen(fd, 'wb') as file:
                mask = os.umask(0)
                os.umask(mask)
                os.fchmod(file.fileno(), 0o666 & ~mask)
                file.write(data)
                file.flush()
                os.fsync(file.fileno())
            try:
                os.link(tmp, path, follow_symlinks=False)
            except FileExistsError:
                verify(path, asset)
            try:
                directory_fd = os.open(path.parent, os.O_RDONLY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except OSError:
                raise SystemExit('Font input is present, but directory durability could not be confirmed; existing files retained.')
        finally:
            os.unlink(tmp)
        verify(path, asset)
    get_compact_font.main(sys.argv[1:])
    print('Pinned font inputs verified. Review rights before redistributing built products.')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile, KeyError):
        raise SystemExit('Font input failed; existing files are retained. Check input and network before retrying.')
