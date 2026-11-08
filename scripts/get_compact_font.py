#!/usr/bin/env python3
"""Obtain or check Grant's pinned, separately distributed build input."""
import hashlib
import io
import os
from pathlib import Path
import stat
import sys
import tempfile
import urllib.request
import urllib.error
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'Resources/Fonts/DeparturePixelZhCompact-Regular.ttf'
URL = 'https://github.com/codingEzio/DeparturePixelZh-OSS/releases/download/v0.1.1/DeparturePixelZh-0.1.1-desktop.zip'
ZIP_SHA = 'b050d6d71b3b79f947ffdd3f0fab2c4f1deb2cc77e9d32cf10942b7d09a265b8'
FONT_SHA = '3e75e623b1ba2c8d7eb52f2ac3ee71c3fbb5c4e0f1426bd34b3c1e071738288b'
FONT_SIZE = 4_975_088
MEMBER = 'DeparturePixelZh-0.1.1-desktop/DeparturePixelZhCompact-Regular.ttf'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check():
    """Accept only a regular, exact input, never a symbolic link."""
    try:
        fd = os.open(DEST, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        raise SystemExit('Compact font missing. Run: python3 scripts/get_compact_font.py')
    except OSError:
        raise SystemExit('Compact font is not an accessible regular file; existing path retained.')
    with os.fdopen(fd, 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise SystemExit('Compact font is not a regular file; existing path retained.')
        if os.fstat(source.fileno()).st_size != FONT_SIZE or digest(source.read()) != FONT_SHA:
            raise SystemExit('Compact font SHA-256 mismatch; existing file retained.')


def obtain():
    try:
        os.lstat(DEST)
    except FileNotFoundError:
        pass
    else:
        check()
        print('Pinned Compact font already present and verified.')
        return
    DEST.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(URL, headers={'User-Agent': 'Grant-source-setup'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            archive = response.read(50_000_001)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise SystemExit('Compact font download failed. Check the network and retry; the destination was not changed.')
    if len(archive) > 50_000_000 or digest(archive) != ZIP_SHA:
        raise SystemExit('Desktop archive SHA-256 mismatch or size limit exceeded.')
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        info = z.getinfo(MEMBER)
        if info.file_size != FONT_SIZE:
            raise SystemExit('Unexpected Compact font size.')
        font = z.read(info)
    if digest(font) != FONT_SHA:
        raise SystemExit('Compact font SHA-256 mismatch.')
    fd, temporary = tempfile.mkstemp(prefix='.compact-font-', dir=DEST.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            current_umask = os.umask(0)
            os.umask(current_umask)
            os.fchmod(output.fileno(), 0o666 & ~current_umask)
            output.write(font)
            output.flush()
            os.fsync(output.fileno())
        if digest(Path(temporary).read_bytes()) != FONT_SHA:
            raise SystemExit('Temporary Compact font verification failed.')
        try:
            os.link(temporary, DEST, follow_symlinks=False)
        except FileExistsError:
            # A concurrent writer wins only if it published the same regular file.
            check()
        try:
            directory_fd = os.open(DEST.parent, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError:
            raise SystemExit('Compact font is present, but directory durability could not be confirmed; existing files retained.')
    finally:
        os.unlink(temporary)
    print('Pinned Compact font verified. Review its rights before redistribution.')


def main(args):
    if args == ['--check']:
        check()
    elif not args:
        obtain()
    else:
        raise SystemExit('Usage: python3 scripts/get_compact_font.py [--check]')


def cli():
    try:
        main(sys.argv[1:])
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit('Compact font download failed. Check the network and retry; the destination was not changed.')
    except (zipfile.BadZipFile, KeyError):
        raise SystemExit('Compact font archive is invalid or missing its expected entry; the destination was not changed.')
    except OSError:
        raise SystemExit('Compact font file operation failed. The destination may already exist; check it before retrying.')


if __name__ == '__main__':
    cli()
