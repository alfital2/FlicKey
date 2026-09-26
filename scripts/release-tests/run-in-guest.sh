#!/bin/bash
# Run after copying the signed app to ~/ReleaseGate/FlicKey.app, copying the
# companion Swift file into UITests, and building the UI runner for testing.
set -euo pipefail
test "$(id -un)" = admin
test -f /Users/admin/.flickey-test-vm
cd /Users/admin/flickey-oss
export FLICKEY_TEST_DERIVED_DATA="$PWD/build/DerivedData"
scripts/tart-grant-accessibility.sh
app=/Users/admin/ReleaseGate/FlicKey.app
codesign --verify --deep --strict "$app"
requirement="$(codesign -dr - "$app" 2>&1 | sed -n 's/^designated => //p')"
test -n "$requirement"
csreq -r="$requirement" -b /private/tmp/flickey-release.csreq
sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \
  "UPDATE access SET csreq=readfile('/private/tmp/flickey-release.csreq') WHERE client='com.talalfi.FlicKey';"
sudo killall tccd 2>/dev/null || true
for scenario in FreshInstallGetsFiniteTrial ActiveTrialEnablesConversion ExpiredTrialBlocksConversionAndOffersPurchase ReleaseIgnoresTrialResetAndLicensedSimulationArguments ClockRollbackCannotReviveExpiredTrial RunningAppLocksWhenTrialExpires; do
pkill -x FlicKey 2>/dev/null || true
/usr/bin/python3 scripts/release-tests/seed-in-guest.py "$scenario"
rm -rf "build/ReleaseEntitlement-$scenario.xcresult"
/usr/bin/xcodebuild test-without-building -project FlicKey.xcodeproj \
  -scheme FlicKeyUITests -destination platform=macOS \
  -derivedDataPath build/DerivedData -resultBundlePath "build/ReleaseEntitlement-$scenario.xcresult" \
  "-only-testing:FlicKeyUITests/ReleaseEntitlementUITests/test$scenario" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=NO
done
