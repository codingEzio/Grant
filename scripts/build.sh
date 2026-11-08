#!/usr/bin/env bash
set -euo pipefail
GRANT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$GRANT_ROOT"
# Signed builds retain their existing destination and require configured identities.
# The unsigned branch never reads signing configuration or updates latest-build.json.
GRANT_MODE=signed
case "${1:-}" in
  "") ;;
  --unsigned) GRANT_MODE=unsigned ;;
  *) printf '%s\n' 'Usage: scripts/build.sh [--unsigned]' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf '%s\n' 'Unexpected build arguments' >&2; exit 2; }
python3 scripts/get_fonts.py --check
GRANT_LINK_FLAGS=()
GRANT_SWIFT_LINK_FLAGS=()
if [[ "$GRANT_MODE" == signed ]]; then
  if [[ -z "${GRANT_SIGN_IDENTITY:-}" || -z "${GRANT_PLUGIN_SIGN_IDENTITY:-}" ]]; then
    [[ -f Local/signing.json ]] || { printf '%s\n' 'Set GRANT_SIGN_IDENTITY and GRANT_PLUGIN_SIGN_IDENTITY, or configure Local/signing.json. Use --unsigned for source-only compilation.' >&2; exit 2; }
    GRANT_SIGN_IDENTITY="${GRANT_SIGN_IDENTITY:-$(python3 -c 'import json; print(json.load(open("Local/signing.json"))["appIdentity"])')}"
    GRANT_PLUGIN_SIGN_IDENTITY="${GRANT_PLUGIN_SIGN_IDENTITY:-$(python3 -c 'import json; print(json.load(open("Local/signing.json"))["pluginIdentity"])')}"
  fi
  [[ -n "$GRANT_SIGN_IDENTITY" && -n "$GRANT_PLUGIN_SIGN_IDENTITY" ]] || { printf '%s\n' 'Signing identities must be nonempty' >&2; exit 2; }
  GRANT_OUTPUT_PARENT=Builds
  GRANT_SCRATCH="$GRANT_ROOT/Local/Build"
else
  GRANT_OUTPUT_PARENT=UnsignedBuilds
  GRANT_LINK_FLAGS=(-Wl,-no_adhoc_codesign)
  GRANT_SWIFT_LINK_FLAGS=(-Xlinker -no_adhoc_codesign)
fi
GRANT_BUILD_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
GRANT_BUILD_DIR="$GRANT_ROOT/Local/$GRANT_OUTPUT_PARENT/$GRANT_BUILD_ID"
if [[ "$GRANT_MODE" == unsigned ]]; then GRANT_SCRATCH="$GRANT_BUILD_DIR/Build"; fi
mkdir -p "$GRANT_SCRATCH" "$GRANT_BUILD_DIR/Grant.app/Contents/MacOS" "$GRANT_BUILD_DIR/Grant.bundle/Contents/MacOS" "$GRANT_BUILD_DIR/GrantSetupReference.app/Contents/MacOS"
GRANT_SDK="$(xcrun --show-sdk-path)"
GRANT_FLAGS=(-isysroot "$GRANT_SDK" -arch arm64 -mmacosx-version-min=27.0 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -I Sources/Shared)
xcrun clang "${GRANT_FLAGS[@]}" -c Sources/Shared/GRGrantView.m -o "$GRANT_SCRATCH/view.o"
xcrun clang "${GRANT_FLAGS[@]}" -c Sources/Shared/GRSudoChannel.m -o "$GRANT_SCRATCH/sudo-channel.o"
xcrun swiftc ${GRANT_SWIFT_LINK_FLAGS[@]+"${GRANT_SWIFT_LINK_FLAGS[@]}"} -O -target arm64-apple-macos27.0 -sdk "$GRANT_SDK" -module-cache-path "$GRANT_SCRATCH/module-cache" \
  -import-objc-header Sources/App/Grant-Bridging-Header.h -I Sources/Shared \
  Sources/App/main.swift "$GRANT_SCRATCH/view.o" "$GRANT_SCRATCH/sudo-channel.o" -framework SystemConfiguration -framework AppKit -framework SwiftUI -framework Security -framework CoreText \
  -o "$GRANT_BUILD_DIR/Grant.app/Contents/MacOS/GrantPreview"
xcrun clang "${GRANT_FLAGS[@]}" ${GRANT_LINK_FLAGS[@]+"${GRANT_LINK_FLAGS[@]}"} -bundle Sources/Plugin/GrantPlugin.m Sources/Shared/GRGrantView.m Sources/Shared/GRContext.m \
  -framework AppKit -framework SystemConfiguration -framework Security -framework CoreText \
  -o "$GRANT_BUILD_DIR/Grant.bundle/Contents/MacOS/Grant"
xcrun clang "${GRANT_FLAGS[@]}" ${GRANT_LINK_FLAGS[@]+"${GRANT_LINK_FLAGS[@]}"} Sources/App/SetupReference.m -framework Cocoa \
  -o "$GRANT_BUILD_DIR/GrantSetupReference.app/Contents/MacOS/GrantSetupReference"
python3 - "$GRANT_BUILD_DIR" "$GRANT_MODE" <<'PY'
from pathlib import Path
import plistlib, shutil,sys,shlex
build=Path(sys.argv[1])
for kind, executable, identifier in [('app','GrantPreview','com.alex.Grant.Preview'),('bundle','Grant','com.alex.Grant.AuthorizationPlugin')]:
    contents=build/('Grant.'+kind)/'Contents'
    resources=contents/'Resources'
    if resources.exists(): shutil.rmtree(resources)
    shutil.copytree('Resources',resources)
    for source,name in [('LICENSE','Grant-MIT.txt'),
                        ('References/Setup/LICENSE','SetupReference-MIT.txt'),
                        ('ARTWORK-LICENSE.md','Grant-Artwork.txt')]:
        shutil.copyfile(source, resources/'Licenses'/name)
    (resources/'Guides').mkdir()
    for name in ['INTEGRATION.md','INTEGRATION.zh-Hans.md','INTEGRATION.zh-Hant.md',
                 'TYPOGRAPHY.md','TYPOGRAPHY.zh-Hans.md','TYPOGRAPHY.zh-Hant.md']:
        shutil.copy(Path('docs')/name,resources/'Guides'/name)
    info={'CFBundleName':'Grant','CFBundleDisplayName':'Grant','CFBundleIdentifier':identifier,
          'CFBundleExecutable':executable,'CFBundlePackageType':'APPL' if kind=='app' else 'BNDL',
          'CFBundleShortVersionString':'0.2.3','CFBundleVersion':'7','LSMinimumSystemVersion':'27.0'}
    if kind=='app': info['NSPrincipalClass']='NSApplication'
    if kind=='app':
        info['GRSettingsValidationVersion']=2
        info['CFBundleURLTypes']=[{'CFBundleURLName':'com.alex.Grant.settings','CFBundleURLSchemes':['grant']}]
        if sys.argv[2]=='signed':
            import os
            deno=shutil.which('deno')
            if not deno: raise SystemExit('Deno runtime not found for setup entry')
            for entry, action in [('GrantSystemSetup','install-system'),('GrantSystemRestore','restore-system')]:
                setup=resources/(entry+'.command')
                setup.write_text('#!/bin/bash\nset -euo pipefail\nexec '+shlex.quote(deno)+' run -A '+shlex.quote(str(Path.cwd()/'scripts/grant.ts'))+' '+action+'\n')
                setup.chmod(0o755)
    (contents/'Info.plist').write_bytes(plistlib.dumps(info,sort_keys=True))
reference=build/'GrantSetupReference.app'/'Contents'
reference_licenses=reference/'Resources'/'Licenses'
reference_licenses.mkdir(parents=True,exist_ok=True)
for source,name in [('LICENSE','Grant-MIT.txt'),
                    ('References/Setup/LICENSE','SetupReference-MIT.txt'),
                    ('ARTWORK-LICENSE.md','Grant-Artwork.txt')]:
    shutil.copyfile(source, reference_licenses/name)
reference_info={'CFBundleName':'Grant Setup Original','CFBundleDisplayName':'Grant Setup Original',
    'CFBundleIdentifier':'com.alex.Grant.SetupOriginal','CFBundleExecutable':'GrantSetupReference',
    'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.3','CFBundleVersion':'7',
    'LSMinimumSystemVersion':'27.0','NSPrincipalClass':'GRSetupReferenceApplication', 'LSUIElement':True}
(reference/'Info.plist').write_bytes(plistlib.dumps(reference_info,sort_keys=True))
PY
mkdir -p "$GRANT_BUILD_DIR/IconBuild"
xcrun actool --compile "$GRANT_BUILD_DIR/IconBuild" --platform macosx --target-device mac \
  --minimum-deployment-target 27.0 --app-icon Grant \
  --output-partial-info-plist "$GRANT_BUILD_DIR/IconBuild/partial.plist" \
  "$GRANT_ROOT/Resources/Grant.icon" > "$GRANT_BUILD_DIR/IconBuild/actool.log" 2>&1
python3 - "$GRANT_BUILD_DIR" <<'PYICON'
from pathlib import Path
import plistlib,shutil,sys
build=Path(sys.argv[1]); compiled=build/'IconBuild'; app=build/'Grant.app'/'Contents'
for name in ['Grant.icns','Assets.car']:
    assert (compiled/name).stat().st_size > 0
    shutil.copy2(compiled/name, app/'Resources'/name)
p=app/'Info.plist'; info=plistlib.loads(p.read_bytes());info.update(plistlib.loads((compiled/'partial.plist').read_bytes()));p.write_bytes(plistlib.dumps(info,sort_keys=True))
PYICON
if [[ "$GRANT_MODE" == signed ]]; then
  codesign --force --sign "$GRANT_PLUGIN_SIGN_IDENTITY" "$GRANT_BUILD_DIR/Grant.bundle"
  codesign --force --sign "$GRANT_SIGN_IDENTITY" "$GRANT_BUILD_DIR/GrantSetupReference.app"
fi
mkdir -p "$GRANT_BUILD_DIR/Grant.app/Contents/Resources/Original"
/usr/bin/ditto "$GRANT_BUILD_DIR/GrantSetupReference.app" "$GRANT_BUILD_DIR/Grant.app/Contents/Resources/Original/GrantSetupReference.app"
if [[ "$GRANT_MODE" == signed ]]; then
  codesign --force --sign "$GRANT_SIGN_IDENTITY" "$GRANT_BUILD_DIR/Grant.app"
  codesign --verify --strict "$GRANT_BUILD_DIR/Grant.bundle"
  codesign --verify --strict "$GRANT_BUILD_DIR/Grant.app"
  codesign --verify --strict "$GRANT_BUILD_DIR/GrantSetupReference.app"
fi
python3 - "$GRANT_BUILD_DIR" "$GRANT_MODE" <<'PY'
from pathlib import Path
import json,hashlib,sys,datetime
files={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['Sources','Resources','docs','References'] for p in sorted(Path(folder).rglob('*')) if p.is_file()}
record={'schemaVersion':1,'directory':sys.argv[1],'version':'0.2.3','builtAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceFiles':files}
if sys.argv[2]=='unsigned': record['signing']='unsigned-source-only'
name='latest-unsigned-build.json' if sys.argv[2]=='unsigned' else 'latest-build.json'
staging=Path('Local')/(name+'.tmp')
staging.write_text(json.dumps(record,indent=2)+'\n'); staging.replace(Path('Local')/name)
print(('Compiled unsigned source candidate ' if sys.argv[2]=='unsigned' else 'Built and verified ')+sys.argv[1]+'; active previews and system authorization were not changed.')
PY
