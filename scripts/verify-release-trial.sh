#!/bin/bash
# Verify the production trial in an unchanged, signed Release app, in Tart.
# Usage: bash scripts/verify-release-trial.sh build/Release/FlicKey.app
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Pass the signed Release app path}"
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
test "$(basename "$app")" = FlicKey.app
codesign --verify --deep --strict "$app"
TART="${FLICKEY_TART_BIN:-/Applications/tart.app/Contents/MacOS/tart}"
VM="${FLICKEY_TEST_VM:-flickey-ui}"
identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
test -n "$identity"
mkdir -p build
swiftc scripts/release-tests/TrialFixture.swift -o build/trial-fixture
codesign --force --sign "$identity" --identifier com.talalfi.FlicKey \
  --timestamp --options runtime build/trial-fixture
scripts/tart.sh start
for attempt in $(seq 1 30); do
  "$TART" exec "$VM" /usr/bin/true >/dev/null 2>&1 && break
  sleep 1
done
scripts/tart.sh sync
"$TART" exec "$VM" mkdir -p /Users/admin/ReleaseGate
tar -C "$(dirname "$app")" -cf - FlicKey.app | "$TART" exec -i "$VM" tar -xpf - -C /Users/admin/ReleaseGate
tar -C build -cf - trial-fixture | "$TART" exec -i "$VM" tar -xpf - -C /Users/admin/ReleaseGate
cleanup() {
  "$TART" exec "$VM" rm -f /Users/admin/ReleaseGate/trial-fixture \
    /Users/admin/flickey-oss/UITests/ReleaseEntitlementUITests.swift || true
}
trap cleanup EXIT
"$TART" exec "$VM" /bin/bash -c '
  set -e
  cd /Users/admin/flickey-oss
  cp scripts/release-tests/ReleaseEntitlementUITests.swift UITests/
  /opt/homebrew/bin/xcodegen generate
  /usr/bin/xcodebuild build-for-testing -project FlicKey.xcodeproj \
    -scheme FlicKeyUITests -destination platform=macOS -derivedDataPath build/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=NO
  /bin/bash scripts/release-tests/run-in-guest.sh
'
