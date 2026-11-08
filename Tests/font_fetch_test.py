"""Exercise font fetching with isolated files and controlled external failures."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = r'''
import hashlib, io, os, pathlib, runpy, sys, urllib.error, urllib.request, zipfile
from unittest import mock
root=pathlib.Path(sys.argv[1]); scenario=sys.argv[2]; mask=int(sys.argv[3],8)
sys.path.insert(0,str(root/'scripts')); import get_compact_font as compact
font=b'fixture-font'; dest=root/'Resources/Fonts/Fixture.ttf'
if scenario.startswith('zip'):
    dest.write_bytes(font)
    if scenario=='zip-bad': raw=b'bad zip'
    else:
        b=io.BytesIO()
        with zipfile.ZipFile(b,'w') as z:z.writestr('wrong',font)
        raw=b.getvalue()
    compact.ZIP_SHA=hashlib.sha256(raw).hexdigest()
else:
    raw=font; compact.main=lambda _:None
if scenario=='existing': dest.write_bytes(font); dest.chmod(0o400)
if scenario=='conflict': dest.write_bytes(b'conflict')
if scenario=='symlink':
    (root/'target').write_bytes(b'keep'); dest.symlink_to(root/'target')
def response(*a,**k):
    if scenario=='network': raise urllib.error.URLError(str(root/'private'))
    return io.BytesIO(raw)
real_link=os.link
real_fsync=os.fsync
calls=0
def link(src,dst,**kwargs):
    if scenario in ('race-same','race-conflict'):
        pathlib.Path(dst).write_bytes(font if scenario=='race-same' else b'conflict')
    return real_link(src,dst,**kwargs)
def sync(fd):
    global calls
    calls+=1
    if scenario=='interrupt' and calls==1: raise OSError(str(root/'private'))
    if scenario=='abrupt' and calls==1: os._exit(91)
    if scenario=='dirsync' and calls==2: raise OSError(str(root/'private'))
    return real_fsync(fd)
os.umask(mask); sys.argv=[str(root/'scripts/get_fonts.py')]
with mock.patch.object(urllib.request,'urlopen',side_effect=response), mock.patch.object(os,'link',side_effect=link), mock.patch.object(os,'fsync',side_effect=sync):
    runpy.run_path(str(root/'scripts/get_fonts.py'),run_name='__main__')
'''

class FontFetch(unittest.TestCase):
    def test_scenarios(self):
        cases = [('new', '022', 0, b'fixture-font', 0o644), ('new', '077', 0, b'fixture-font', 0o600),
                 ('existing', '077', 0, b'fixture-font', 0o400), ('conflict', '077', 1, b'conflict', None),
                 ('symlink', '077', 1, b'keep', None), ('race-same', '077', 0, b'fixture-font', None),
                 ('race-conflict', '077', 1, b'conflict', None), ('interrupt', '077', 1, None, None),
                 ('dirsync', '077', 1, b'fixture-font', None), ('abrupt', '077', 1, None, None), ('network', '077', 1, None, None),
                 ('zip-bad', '077', 1, b'fixture-font', None), ('zip-member', '077', 1, b'fixture-font', None)]
        for scenario, mask, failed, content, mode in cases:
            with self.subTest(scenario=scenario, mask=mask), tempfile.TemporaryDirectory() as temp:
                root=Path(temp); (root/'scripts').mkdir(); (root/'Resources/Licenses').mkdir(parents=True); (root/'Resources/Fonts').mkdir()
                for name in ('get_fonts.py', 'get_compact_font.py'):
                    (root/'scripts'/name).write_bytes((ROOT/'scripts'/name).read_bytes())
                data=b'fixture-font'; asset={'path':'Resources/Fonts/Fixture.ttf','bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'sourceURL':'https://example.invalid/font'}
                (root/'Resources/Licenses/fonts.json').write_text(json.dumps({'assets':[asset]}))
                result=subprocess.run([sys.executable,'-B','-c',RUNNER,str(root),scenario,mask],capture_output=True,text=True,timeout=15)
                self.assertEqual(result.returncode != 0, bool(failed))
                self.assertNotIn(str(root), result.stdout+result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                target=root/'Resources/Fonts/Fixture.ttf'
                if content is None: self.assertFalse(target.exists())
                else: self.assertEqual(target.read_bytes(), content)
                if scenario=='symlink': self.assertTrue(target.is_symlink())
                if mode is not None: self.assertEqual(target.stat().st_mode & 0o777, mode)
                if scenario=='dirsync': self.assertIn('directory durability could not be confirmed', result.stderr)
                leftovers=list(target.parent.glob('.font-*'))
                if scenario=='abrupt':
                    self.assertEqual(result.returncode, 91)
                    self.assertEqual(len(leftovers), 1)
                    retry=subprocess.run([sys.executable,'-B','-c',RUNNER,str(root),'new','077'],capture_output=True,text=True,timeout=15)
                    self.assertEqual(retry.returncode, 0)
                    self.assertEqual(target.read_bytes(), b'fixture-font')
                    self.assertTrue(leftovers[0].exists())
                else:
                    self.assertFalse(leftovers)

if __name__=='__main__': unittest.main()
