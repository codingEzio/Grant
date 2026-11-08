"""Synthetic regressions for interruption-safe review pin publication."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

script = Path(__file__).resolve().parent.parent / 'scripts/review_source.py'
spec = importlib.util.spec_from_file_location('review_source', script)
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class ReviewUpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='grant-review-update-')
        self.root = Path(self.temp.name).resolve()
        self.scripts = self.root / 'scripts'
        self.scripts.mkdir()
        self.fd = os.open(self.scripts, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.output = self.scripts / 'pins.json'
        self.output.write_bytes(b'old')
        self.other = self.root / 'unrelated'
        self.other.write_bytes(b'preserve')

    def tearDown(self):
        os.close(self.fd)
        self.temp.cleanup()

    def publish(self):
        return review.atomic_replace(self.fd, self.scripts, 'pins.json', b'new')

    def retained(self):
        return list(self.scripts.glob('.grant-review-previous-*'))

    def test_normal_and_repeat_preserve_previous(self):
        first = self.publish()
        self.assertEqual(self.output.read_bytes(), b'new')
        self.assertEqual((self.scripts / first).read_bytes(), b'old')
        second = self.publish()
        self.assertEqual((self.scripts / second).read_bytes(), b'new')
        self.assertEqual(self.other.read_bytes(), b'preserve')

    def test_symlink_and_nonregular_are_rejected(self):
        self.output.unlink()
        self.output.symlink_to(self.other)
        with self.assertRaises(ValueError): self.publish()
        self.assertTrue(self.output.is_symlink())
        self.assertEqual(self.other.read_bytes(), b'preserve')
        self.output.unlink()
        self.output.mkdir()
        with self.assertRaises(ValueError): self.publish()

    def test_write_failure_keeps_original_and_staged(self):
        with patch.object(review.os, 'fsync', side_effect=OSError('fixture')):
            with self.assertRaises(OSError): self.publish()
        self.assertEqual(self.output.read_bytes(), b'old')
        self.assertEqual(len(list(self.scripts.glob('.grant-review-new-*'))), 1)

    def test_parent_replacement_cannot_touch_unrelated_directory(self):
        outsider = self.root / 'other-scripts'
        outsider.mkdir()
        (outsider / 'pins.json').write_bytes(b'unrelated')
        moved = self.root / 'moved-scripts'
        real = review.rename_exclusive
        calls = 0
        def race(fd, source, destination):
            nonlocal calls
            calls += 1
            if calls == 1:
                os.rename(self.scripts, moved)
                self.scripts.symlink_to(outsider, target_is_directory=True)
            real(fd, source, destination)
        with patch.object(review, 'rename_exclusive', side_effect=race):
            with self.assertRaises(ValueError): self.publish()
        self.assertEqual((outsider / 'pins.json').read_bytes(), b'unrelated')
        self.assertEqual(next(moved.glob('.grant-review-previous-*')).read_bytes(), b'old')
        self.assertEqual(next(moved.glob('.grant-review-new-*')).read_bytes(), b'new')

    def test_interrupt_after_syscall_retains_original_and_recovery(self):
        real = review.rename_exclusive
        def interrupted(fd, source, destination):
            real(fd, source, destination)
            raise KeyboardInterrupt()
        with patch.object(review, 'rename_exclusive', side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt): self.publish()
        previous = self.retained()
        self.assertEqual(len(previous), 1)
        self.assertEqual(previous[0].read_bytes(), b'old')
        self.assertEqual(next(self.scripts.glob('.grant-review-new-*')).read_bytes(), b'new')
        review.rename_exclusive(self.fd, previous[0].name, 'pins.json')
        self.assertEqual(self.output.read_bytes(), b'old')
        self.publish()
        self.assertEqual(self.output.read_bytes(), b'new')

    def test_interrupt_after_publication_retains_both_versions(self):
        real = review.rename_exclusive
        calls = 0
        def interrupted(fd, source, destination):
            nonlocal calls
            calls += 1
            real(fd, source, destination)
            if calls == 2:
                raise KeyboardInterrupt()
        with patch.object(review, 'rename_exclusive', side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt): self.publish()
        self.assertEqual(self.output.read_bytes(), b'new')
        self.assertEqual(self.retained()[0].read_bytes(), b'old')

    def test_late_arrival_is_never_overwritten_or_removed(self):
        real = review.rename_exclusive
        calls = 0
        def race(fd, source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                self.output.write_bytes(b'late arrival')
            real(fd, source, destination)
        with patch.object(review, 'rename_exclusive', side_effect=race):
            with self.assertRaises(OSError): self.publish()
        self.assertEqual(self.output.read_bytes(), b'late arrival')
        self.assertEqual(self.retained()[0].read_bytes(), b'old')
        self.assertEqual(next(self.scripts.glob('.grant-review-new-*')).read_bytes(), b'new')

    def test_entrypoint_symlink_rejected_then_normal_rerun(self):
        shutil.copy2(script, self.scripts / 'review_source.py')
        helper = self.scripts / 'public_prepare.ts'
        helper.write_text('const reviewHash = "' + '0' * 64 + '";\n')
        sidecar = self.scripts / 'source-review-hashes.json'
        sidecar.write_text('{}\n')
        selected = ['public-source.json', 'scripts/public_prepare.ts', 'scripts/source-review-hashes.json']
        (self.root / 'public-source.json').write_text(json.dumps({'files': selected}))
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), 'add', *selected], check=True)
        sidecar.unlink()
        sidecar.symlink_to(self.other)
        command = [sys.executable, str(self.scripts / 'review_source.py'), '--reviewed']
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertEqual(self.other.read_bytes(), b'preserve')
        sidecar.unlink()
        sidecar.write_text('{}\n')
        result = subprocess.run(command, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('public-source.json', json.loads(sidecar.read_text()))
        self.assertNotIn('0' * 64, helper.read_text())


if __name__ == '__main__': unittest.main()
