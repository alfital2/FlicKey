#!/bin/bash
# Runs the auto-switch rewrite-span edge cases against the REAL
# Sources/OnScreenSpan.swift. Needs only Command Line Tools (no Xcode), so it
# works where `xcodebuild test` cannot run. Exit 1 if any case corrupts the field.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -O Sources/OnScreenSpan.swift scripts/span-edge-cases/main.swift -o "$out/span_sim"
"$out/span_sim"
