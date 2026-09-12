#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
unset XCODE_XCCONFIG_FILE
export PATH="$PWD/scripts/vm-bin:$PATH"
exec "$PWD/scripts/test.sh" "$@"
