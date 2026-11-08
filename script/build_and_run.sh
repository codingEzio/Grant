#!/usr/bin/env bash
set -euo pipefail
GRANT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$GRANT_ROOT"
# Build and verify the replacement first; only then stop this candidate.
./grant build
GRANT_APP="$(python3 -c 'import json; print(json.load(open("Local/latest-build.json"))["directory"] + "/Grant.app")')"
case "${1:-run}" in
  --stage) exit 0 ;;
  --debug) exec lldb -- "$GRANT_APP/Contents/MacOS/GrantPreview" --state-dir "$GRANT_ROOT/Local/Preview" ;;
  run|--verify|--logs|--telemetry)
    ./grant stop-preview
    ./grant preview
    if [[ "${1:-run}" == --verify ]]; then
      "$GRANT_APP/Contents/MacOS/GrantPreview" --verify-running
    fi
    if [[ "${1:-run}" == --logs || "${1:-run}" == --telemetry ]]; then
      exec /usr/bin/log stream --info --predicate 'process == "GrantPreview"'
    fi
    ;;
  *) printf '%s\n' 'Usage: script/build_and_run.sh [--stage|--debug|--verify|--logs|--telemetry]' >&2; exit 2 ;;
esac
