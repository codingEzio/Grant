"""Synthetic regression coverage for review pin publication; no Grant runs."""
import importlib.util
import os
import json
import shutil
import subprocess
import sys
from pathlib import Path
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
        self.output = self.root / 'pins.json'
        self.output.write_bytes(b'old')
        self.other = self.root / 'unrelated'
        self.other.write_bytes(b'preserve')

    def tearDown(self):
        self.temp.cleanup()

    def test_entrypoint_rejects_symlink_and_recovers(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        shutil.copy2(script, scripts / 'review_source.py')
        helper = scripts / 'public_prepare.ts'
        helper.write_text('const reviewHash = "' + '0' * 64 + '";\n')
        sidecar = scripts / 'source-review-hashes.json'
        sidecar.write_text('{}\n')
        selected = ['public-source.json', 'scripts/public_prepare.ts', 'scripts/source-review-hashes.json']
        (self.root / 'public-source.json').write_text(json.dumps({'files': selected}))
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), 'add', *selected], check=True)
        sidecar.unlink()
        sidecar.symlink_to(self.other)
        result = subprocess.run([sys.executable, str(scripts / 'review_source.py'), '--reviewed'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.other.read_bytes(), b'preserve')
        self.assertTrue(sidecar.is_symlink())
        sidecar.unlink()
        sidecar.write_text('{}\n')
        copy = scripts / 'review_source.py'
        original_script = copy.read_text()
        target = '    atomic_replace(helper_path, updated, outputs[helper], helper_original)'
        self.assertIn(target, original_script)
        copy.write_text(original_script.replace(target, "    raise OSError('fixture second-write failure')"))
        result = subprocess.run([sys.executable, str(copy), '--reviewed'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('0' * 64, helper.read_text())
        self.assertIn('public-source.json', json.loads(sidecar.read_text()))
        copy.write_text(original_script)
        result = subprocess.run([sys.executable, str(copy), '--reviewed'], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('public-source.json', json.loads(sidecar.read_text()))
        self.assertNotIn('0' * 64, helper.read_text())

    def test_normal_atomic_update(self):
        review.atomic_replace(self.output, b'new')
        self.assertEqual(self.output.read_bytes(), b'new')
        self.assertEqual(self.other.read_bytes(), b'preserve')
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['pins.json', 'unrelated'])

    def test_symlink_and_nonregular_are_rejected(self):
        self.output.unlink()
        self.output.symlink_to(self.other)
        with self.assertRaises(ValueError):
            review.atomic_replace(self.output, b'new')
        self.assertTrue(self.output.is_symlink())
        self.assertEqual(self.other.read_bytes(), b'preserve')
        self.output.unlink()
        self.output.mkdir()
        with self.assertRaises(ValueError):
            review.atomic_replace(self.output, b'new')

    def test_write_failure_retains_original(self):
        with patch.object(review.os, 'fsync', side_effect=OSError('fixture write failure')):
            with self.assertRaises(OSError):
                review.atomic_replace(self.output, b'new')
        self.assertEqual(self.output.read_bytes(), b'old')
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['pins.json', 'unrelated'])

    def test_concurrent_symlink_is_rejected_and_restored(self):
        real_swap = review.swap
        saved = self.root / 'concurrent-original'
        calls = 0
        def racing_swap(source, destination):
            nonlocal calls
            calls += 1
            if calls == 1:
                os.rename(destination, saved)
                destination.symlink_to(self.other)
            real_swap(source, destination)
        with patch.object(review, 'swap', side_effect=racing_swap):
            with self.assertRaises(ValueError):
                review.atomic_replace(self.output, b'new')
        self.assertTrue(self.output.is_symlink())
        self.assertEqual(saved.read_bytes(), b'old')
        self.assertEqual(self.other.read_bytes(), b'preserve')
        self.assertFalse(any(p.name.startswith('.grant-review-') for p in self.root.iterdir()))

    def test_displaced_read_failure_restores_original(self):
        real_read = review.read_checked
        calls = 0
        def failing_read(path, expected):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('fixture read failure')
            return real_read(path, expected)
        with patch.object(review, 'read_checked', side_effect=failing_read):
            with self.assertRaises(ValueError):
                review.atomic_replace(self.output, b'new')
        self.assertEqual(self.output.read_bytes(), b'old')
        self.assertFalse(any(p.name.startswith('.grant-review-') for p in self.root.iterdir()))

    def test_concurrent_inplace_edit_is_preserved(self):
        real_swap = review.swap
        calls = 0
        def racing_swap(source, destination):
            nonlocal calls
            calls += 1
            if calls == 1:
                destination.write_bytes(b'concurrent edit')
            real_swap(source, destination)
        with patch.object(review, 'swap', side_effect=racing_swap):
            with self.assertRaises(ValueError):
                review.atomic_replace(self.output, b'new')
        self.assertEqual(self.output.read_bytes(), b'concurrent edit')
        self.assertFalse(any(p.name.startswith('.grant-review-') for p in self.root.iterdir()))

    def test_concurrent_regular_file_is_not_lost(self):
        real_swap = review.swap
        saved = self.root / 'concurrent-original'
        calls = 0
        def racing_swap(source, destination):
            nonlocal calls
            calls += 1
            if calls == 1:
                os.rename(destination, saved)
                destination.write_bytes(b'concurrent')
            real_swap(source, destination)
        with patch.object(review, 'swap', side_effect=racing_swap):
            with self.assertRaises(ValueError):
                review.atomic_replace(self.output, b'new')
        self.assertEqual(self.output.read_bytes(), b'concurrent')
        self.assertEqual(saved.read_bytes(), b'old')


if __name__ == '__main__':
    unittest.main()
