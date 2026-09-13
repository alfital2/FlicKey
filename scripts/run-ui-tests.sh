#!/usr/bin/env bash
#
# run-ui-tests.sh — run the standard local UI test suite.
#
# ⚠️  These tests DRIVE THE REAL APP: they open windows, click, and type, so they
#     take over the screen/keyboard for ~1 minute. Don't touch the mouse or
#     keyboard while it runs. (This is why UI tests live in their own scheme and
#     never run as part of the normal `xcodebuild test -scheme FlicKey`.)
#
# Covers Settings, TextEdit conversion and auto-switching, per-app routing,
# Spotlight, and the status menu. Live browsers and Teams remain opt-in.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Regenerating project from project.yml"
xcodegen generate >/dev/null

echo
echo "⚠️  The UI tests will CONTROL THE SCREEN for ~1 minute. Don't touch the"
echo "    mouse or keyboard once they start."
for i in 5 4 3 2 1; do printf "\r    starting in %ss…" "$i"; sleep 1; done
echo

LOG="build/ui-test.log"
RESULT_BUNDLE="build/ui-test.xcresult"
mkdir -p build
rm -rf "$RESULT_BUNDLE"

# Run, streaming a filtered view, but capture xcodebuild's REAL exit code
# (PIPESTATUS) so the script's result reflects the tests — not grep.
set +e
xcodebuild test \
  -project FlicKey.xcodeproj \
  -scheme FlicKeyUITests \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_HARDENED_RUNTIME=NO \
  -skip-testing:FlicKeyUITests/BrowserIntegrationUITests \
  -skip-testing:FlicKeyUITests/FirefoxBrowserIntegrationUITests \
  -skip-testing:FlicKeyUITests/TeamsIntegrationUITests \
  -resultBundlePath "$RESULT_BUNDLE" \
  2>&1 | tee "$LOG" \
  | grep -iE "Test Case .* (passed|failed)|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|error:|STEP ▸" \
  | sed -E 's/.*STEP ▸ /   ▸ /'
status=${PIPESTATUS[0]}
set -e

echo
echo "──────────────────────────────────────────────"
if [ "$status" -eq 0 ]; then
  echo "✅ UI TESTS PASSED"
else
  echo "❌ UI TESTS FAILED (xcodebuild exit $status)"
  echo "   Failing cases:"
  grep -iE "Test Case .* failed|error:|XCTAssert" "$LOG" | sed 's/^/     /' | tail -20
fi
echo "   Full log:      $LOG"
echo "   Result bundle: $RESULT_BUNDLE  (open in Xcode for screenshots/details)"
echo "──────────────────────────────────────────────"
exit "$status"
