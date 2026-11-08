"""Isolated tests for external font installation; no network or real fonts."""
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import sys
import subprocess
import textwrap
import unittest
from unittest import mock
import zipfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('compact_input', Path(__file__).resolve().parents[1] / 'scripts/get_compact_font.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class CompactInputTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.original_dest, self.original_sha, self.original_size, self.original_zip = mod.DEST, mod.FONT_SHA, mod.FONT_SIZE, mod.ZIP_SHA
        self.font = b'synthetic font for atomic input test'
        mod.DEST = self.directory / 'font.ttf'
        mod.FONT_SHA = hashlib.sha256(self.font).hexdigest()
        mod.FONT_SIZE = len(self.font)
        out = io.BytesIO()
        with zipfile.ZipFile(out, 'w') as z:
            z.writestr(mod.MEMBER, self.font)
        self.archive = out.getvalue()
        mod.ZIP_SHA = hashlib.sha256(self.archive).hexdigest()
        self.url = mock.patch.object(mod.urllib.request, 'urlopen', side_effect=lambda *a, **kw: io.BytesIO(self.archive))
        self.url.start()

    def tearDown(self):
        self.url.stop()
        mod.DEST, mod.FONT_SHA, mod.FONT_SIZE, mod.ZIP_SHA = self.original_dest, self.original_sha, self.original_size, self.original_zip
        self.tmp.cleanup()

    def test_create_and_idempotent(self):
        mod.obtain()
        self.assertEqual(mod.DEST.read_bytes(), self.font)
        self.url.stop()
        with mock.patch.object(mod.urllib.request, 'urlopen', side_effect=AssertionError('unexpected network')):
            mod.obtain()
        self.url.start()
        self.assertEqual(list(self.directory.iterdir()), [mod.DEST])

    def test_new_file_respects_umask_and_existing_mode_is_preserved(self):
        for mask, expected in [(0o022, 0o644), (0o077, 0o600)]:
            previous = os.umask(mask)
            try:
                mod.obtain()
            finally:
                os.umask(previous)
            self.assertEqual(mod.DEST.stat().st_mode & 0o777, expected)
            os.chmod(mod.DEST, 0o400)
            mod.obtain()
            self.assertEqual(mod.DEST.stat().st_mode & 0o777, 0o400)
            mod.DEST.unlink()

    def test_existing_different_or_symlink_is_preserved(self):
        mod.DEST.write_bytes(b'different')
        with self.assertRaises(SystemExit): mod.obtain()
        self.assertEqual(mod.DEST.read_bytes(), b'different')
        mod.DEST.unlink()
        other = self.directory / 'other'
        other.write_bytes(self.font)
        mod.DEST.symlink_to(other)
        with self.assertRaises(SystemExit): mod.obtain()
        self.assertTrue(mod.DEST.is_symlink())
        self.assertEqual(other.read_bytes(), self.font)

    def test_competing_writer(self):
        real_link = os.link
        for content, succeeds in [(self.font, True), (b'other', False)]:
            def race(src, dst, **kwargs):
                Path(dst).write_bytes(content)
                return real_link(src, dst, **kwargs)
            with mock.patch.object(mod.os, 'link', side_effect=race):
                if succeeds: mod.obtain()
                else:
                    with self.assertRaises(SystemExit): mod.obtain()
            self.assertEqual(mod.DEST.read_bytes(), content)
            self.assertEqual(list(self.directory.iterdir()), [mod.DEST])
            mod.DEST.unlink()

    def test_competing_symlink_is_rejected(self):
        other = self.directory / 'other'
        other.write_bytes(self.font)
        real_link = os.link
        def race(src, dst, **kwargs):
            Path(dst).symlink_to(other)
            return real_link(src, dst, **kwargs)
        with mock.patch.object(mod.os, 'link', side_effect=race):
            with self.assertRaises(SystemExit): mod.obtain()
        self.assertTrue(mod.DEST.is_symlink())
        self.assertEqual(other.read_bytes(), self.font)
        self.assertEqual(len(list(self.directory.iterdir())), 2)

    def test_cli_errors_are_clear_and_do_not_expose_paths(self):
        runner = textwrap.dedent("""
            import hashlib, importlib.util, io, os, pathlib, sys, urllib.error, zipfile
            from unittest import mock
            spec = importlib.util.spec_from_file_location('input', sys.argv[1])
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            folder = pathlib.Path(sys.argv[2]); scenario = sys.argv[3]
            mod.DEST = folder / 'font.ttf'
            font = b'synthetic'
            mod.FONT_SHA = hashlib.sha256(font).hexdigest(); mod.FONT_SIZE = len(font)
            out = io.BytesIO()
            with zipfile.ZipFile(out, 'w') as z: z.writestr(mod.MEMBER, font)
            archive = b'bad zip' if scenario == 'zip' else out.getvalue()
            mod.ZIP_SHA = hashlib.sha256(archive).hexdigest()
            def response(*args, **kwargs):
                if scenario == 'network': raise urllib.error.URLError(str(folder / 'private-marker'))
                return io.BytesIO(archive)
            real_fsync = os.fsync
            calls = 0
            def sync(fd):
                global calls
                calls += 1
                if scenario == 'dirsync' and calls == 2: raise OSError(str(folder / 'private-marker'))
                return real_fsync(fd)
            def link(*args, **kwargs): raise OSError(str(folder / 'private-marker'))
            sys.argv = ['get_compact_font.py']
            with mock.patch.object(mod.urllib.request, 'urlopen', side_effect=response), mock.patch.object(mod.os, 'fsync', side_effect=sync):
                if scenario == 'link':
                    with mock.patch.object(mod.os, 'link', side_effect=link): mod.cli()
                else: mod.cli()
        """)
        script = str(Path(__file__).resolve().parents[1] / 'scripts/get_compact_font.py')
        sentinel = self.directory / 'keep'
        sentinel.write_bytes(b'unchanged')
        for scenario in ('network', 'link', 'zip', 'dirsync'):
            result = subprocess.run([sys.executable, '-B', '-c', runner, script, str(self.directory), scenario], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('Traceback', result.stderr)
            self.assertNotIn(str(self.directory), result.stderr)
            self.assertNotIn('private-marker', result.stderr)
            self.assertNotIn(str(self.directory), result.stdout)
            expected = {'network': 'download failed', 'link': 'file operation failed', 'zip': 'archive is invalid', 'dirsync': 'directory durability could not be confirmed'}
            self.assertIn(expected[scenario], result.stderr)
            self.assertEqual(sentinel.read_bytes(), b'unchanged')
            if scenario == 'dirsync':
                self.assertTrue(mod.DEST.is_file())
                self.assertIn('font is present', result.stderr)
                mod.DEST.unlink()
            else:
                self.assertFalse(mod.DEST.exists())
            self.assertEqual(list(self.directory.iterdir()), [sentinel])

    def test_write_failure_removes_only_own_temp(self):
        retained = self.directory / '.compact-font-other'
        retained.write_bytes(b'other operation')
        with mock.patch.object(mod.os, 'fsync', side_effect=OSError('fixture interruption')):
            with self.assertRaises(OSError): mod.obtain()
        self.assertFalse(mod.DEST.exists())
        self.assertEqual(retained.read_bytes(), b'other operation')
        self.assertEqual(list(self.directory.iterdir()), [retained])
        mod.obtain()
        self.assertEqual(mod.DEST.read_bytes(), self.font)
        self.assertEqual(retained.read_bytes(), b'other operation')

    def test_abrupt_interruption_retry(self):
        pid = os.fork()
        if pid == 0:
            mod.os.fsync = lambda _: os._exit(91)
            mod.obtain()
            os._exit(0)
        _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 91)
        self.assertFalse(mod.DEST.exists())
        leftovers = list(self.directory.iterdir())
        self.assertEqual(len(leftovers), 1)
        mod.obtain()
        self.assertEqual(mod.DEST.read_bytes(), self.font)
        self.assertTrue(leftovers[0].exists())


if __name__ == '__main__':
    unittest.main()
