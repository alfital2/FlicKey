#!/bin/bash
# Deterministic bug-hunting soak. Drives FlicKey's real decision components with
# seeded random event streams and checks invariants after every step; any failure
# prints the exact seed to reproduce it.
#
# Usage:
#   scripts/soak.sh              # ~10 minutes total (100s per soak class)
#   scripts/soak.sh 600          # 600s per soak class (~1 hour total)
#
# CI runs the same tests WITHOUT this script (bounded, ~10s) via a normal
# `xcodebuild test`; this script only turns on the long timed mode.
set -euo pipefail
cd "$(dirname "$0")/.."

SECS="${1:-100}"
echo "$SECS" > /tmp/flickey-soak-seconds
trap 'rm -f /tmp/flickey-soak-seconds' EXIT

echo "▶ Soaking each class for ${SECS}s (Ctrl-C to stop)…"
xcodebuild test -project FlicKey.xcodeproj -scheme FlicKey -destination 'platform=macOS' \
  -only-testing:FlicKeyTests/DetectionSoakTests \
  -only-testing:FlicKeyTests/MemorySoakTests \
  -only-testing:FlicKeyTests/StateSoakTests \
  2>&1 | grep -E "Test Case.*(passed|failed)|invariant broken|seed=|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)"
