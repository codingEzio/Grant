"""Exercise build.sh branching using recorder compilers/signers; no native code runs."""
from pathlib import Path
import json, os, shutil, subprocess, tempfile
root = Path(__file__).resolve().parent.parent
(root / 'Local').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='delete_after_use_build_modes_', dir=root / 'Local') as temporary:
    fixture = Path(temporary) / 'source with spaces'
    fixture.mkdir()
    for directory in ['Sources', 'Resources', 'docs', 'References']:
        shutil.copytree(root / directory, fixture / directory)
    (fixture / 'scripts').mkdir()
    for name in ['LICENSE', 'ARTWORK-LICENSE.md']:
        shutil.copy2(root / name, fixture / name)
    for script in ['build.sh', 'get_compact_font.py', 'get_fonts.py']:
        shutil.copy2(root / 'scripts' / script, fixture / 'scripts' / script)
    (fixture / 'Local').mkdir()
    tools = fixture / 'mock-tools'
    tools.mkdir()
    recorder = '''#!/usr/bin/env python3
from pathlib import Path
import json,sys,plistlib
with open('Local/tool-calls.jsonl','a') as log: log.write(json.dumps([Path(sys.argv[0]).name,*sys.argv[1:]])+'\\n')
a=sys.argv[1:]
if Path(sys.argv[0]).name=='codesign': sys.exit(0)
if a==['--show-sdk-path']: print('/fixture-sdk'); sys.exit(0)
if a[0]=='actool':
 p=Path(a[a.index('--compile')+1]);p.mkdir(exist_ok=True)
 for name in ['Grant.icns','Assets.car']: (p/name).write_bytes(b'FIXTURE_ONLY')
 Path(a[a.index('--output-partial-info-plist')+1]).write_bytes(plistlib.dumps({'CFBundleIconName':'Grant'}))
else:
 p=Path(a[a.index('-o')+1]);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'FIXTURE_ONLY_NOT_EXECUTABLE')
'''
    for name in ['xcrun', 'codesign']:
        target = tools / name
        target.write_text(recorder)
        target.chmod(0o755)
    environment = dict(os.environ)
    environment['PATH'] = str(tools) + os.pathsep + environment['PATH']
    environment.pop('GRANT_SIGN_IDENTITY', None)
    environment.pop('GRANT_PLUGIN_SIGN_IDENTITY', None)
    config = fixture / 'Local/signing.json'
    config.write_text(json.dumps({'appIdentity': 'fixture-app', 'pluginIdentity': 'fixture-plugin'}))
    log = fixture / 'Local/tool-calls.jsonl'
    def build(arguments=(), overrides=None):
        log.unlink(missing_ok=True)
        result = subprocess.run(['/bin/bash', 'scripts/build.sh', *arguments], cwd=fixture,
                                env={**environment, **(overrides or {})}, capture_output=True)
        assert result.returncode == 0, result.stderr.decode()
        return [json.loads(line) for line in log.read_text().splitlines()]
    calls = build()
    signs = [call[call.index('--sign')+1] for call in calls if call[0]=='codesign' and '--sign' in call]
    assert signs == ['fixture-plugin', 'fixture-app', 'fixture-app'], signs
    assert (fixture / 'Local/latest-build.json').exists()
    assert not (fixture / 'Local/latest-unsigned-build.json').exists()
    calls = build(overrides={'GRANT_SIGN_IDENTITY':'override-app', 'GRANT_PLUGIN_SIGN_IDENTITY':'override-plugin'})
    signs = [call[call.index('--sign')+1] for call in calls if call[0]=='codesign' and '--sign' in call]
    assert signs == ['override-plugin', 'override-app', 'override-app'], signs
    signed = (fixture / 'Local/latest-build.json').read_bytes()
    config.write_text('invalid JSON must not be read by unsigned build')
    calls = build(['--unsigned'])
    assert not any(call[0]=='codesign' for call in calls)
    assert (fixture / 'Local/latest-build.json').read_bytes() == signed
    unsigned = json.loads((fixture / 'Local/latest-unsigned-build.json').read_text())
    assert unsigned['signing']=='unsigned-source-only'
    assert '/UnsignedBuilds/' in unsigned['directory']
    assert not list(Path(unsigned['directory']).rglob('GrantSystem*.command'))
    for bundle in ['Grant.app', 'Grant.bundle', 'GrantSetupReference.app']:
        for source, name in [('LICENSE', 'Grant-MIT.txt'),
                             ('References/Setup/LICENSE', 'SetupReference-MIT.txt'),
                             ('ARTWORK-LICENSE.md', 'Grant-Artwork.txt')]:
            assert (Path(unsigned['directory']) / bundle / 'Contents/Resources/Licenses' / name).read_bytes() == (fixture / source).read_bytes()
    links = [call for call in calls if call[0]=='xcrun' and '-o' in call and '-c' not in call]
    assert len(links)==3
    assert all('-no_adhoc_codesign' in call or '-Wl,-no_adhoc_codesign' in call for call in links)
    config.unlink()
    log.unlink()
    failed = subprocess.run(['/bin/bash','scripts/build.sh'],cwd=fixture,env=environment,capture_output=True)
    assert failed.returncode != 0 and not log.exists(), 'Unconfigured signed build must fail before toolchain/signing'
print('PASS signed defaults, explicit overrides, unsigned isolation and missing-identity refusal; recorder tools only')
