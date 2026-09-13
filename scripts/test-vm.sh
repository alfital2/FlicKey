#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
unset XCODE_XCCONFIG_FILE
export PATH="$PWD/scripts/vm-bin:$PATH"

set +e
"$PWD/scripts/test.sh" "$@"
status=$?
set -e

if [[ -n "${FLICKEY_VM_RESULTS:-}" ]]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$FLICKEY_VM_RESULTS"
    for result in build/*.xcresult; do
        [[ -e "$result" ]] || continue
        cp -R "$result" "$FLICKEY_VM_RESULTS/$(basename "${result%.xcresult}")-$stamp.xcresult"
    done
    cp build/test-transcript.txt "$FLICKEY_VM_RESULTS/test-transcript-$stamp.txt" 2>/dev/null || true
fi
exit "$status"
