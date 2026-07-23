#!/usr/bin/env bash
#
# build-dmg.sh — produce a clean, signed, notarized FlicKey.dmg for distribution.
#
# Why build via `-target` (not `-scheme`): the FlicKey scheme enables code
# coverage for its test action, and building the Release product *through the
# scheme* leaks `-fprofile-instr-generate` into the shipped binary (runtime
# overhead, stray .profraw files, embedded local source paths). Building the
# target directly avoids that. The Release config also sets
# CLANG_ENABLE_CODE_COVERAGE=NO as defence in depth (see project.yml).
#
# Notarization: the DMG is submitted to Apple's notary service and the ticket
# is stapled before the file is considered done. Requires a Developer ID
# Application certificate and a stored notarytool keychain profile named
# "flickey-notarize" (set up once with `xcrun notarytool store-credentials`).
#
# Usage:  scripts/build-dmg.sh
# Output: dist/FlicKey.dmg   (asset name the landing page hard-codes)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="FlicKey"
BUILD_DIR="$ROOT/build/Release"
DIST_DIR="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Locate the Developer ID Application certificate — required for notarization.
DEV_ID_CERT=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$DEV_ID_CERT" ]; then
  echo "ERROR: No 'Developer ID Application' certificate found in keychain." >&2
  echo "       Create one in Xcode → Settings → Accounts → Manage Certificates." >&2
  exit 1
fi
echo "==> Signing identity: $DEV_ID_CERT"

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate >/dev/null

echo "==> Running tests"
xcodebuild test -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -destination 'platform=macOS' >/dev/null

echo "==> Building Release (via -target, no coverage instrumentation)"
rm -rf "$BUILD_DIR"
xcodebuild -project "$APP_NAME.xcodeproj" -target "$APP_NAME" \
  -configuration Release CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  CODE_SIGN_IDENTITY="$DEV_ID_CERT" \
  DEVELOPMENT_TEAM="58XL8H22S9" \
  build >/dev/null

APP="$BUILD_DIR/$APP_NAME.app"

# Re-sign Sparkle's bundled sub-binaries with our Developer ID cert.
# Sparkle ships pre-signed with its own certificate, which Apple rejects for
# notarization. We must re-sign every nested component inside-out before the
# outer .app bundle, otherwise codesign invalidates the inner signatures.
echo "==> Re-signing Sparkle sub-components with Developer ID"
SPARKLE_B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

for XPC in "$SPARKLE_B/XPCServices/"*.xpc; do
  codesign --force --sign "$DEV_ID_CERT" --timestamp --options runtime "$XPC"
done
codesign --force --sign "$DEV_ID_CERT" --timestamp --options runtime \
  "$SPARKLE_B/Updater.app/Contents/MacOS/Updater"
codesign --force --sign "$DEV_ID_CERT" --timestamp --options runtime \
  "$SPARKLE_B/Updater.app"
codesign --force --sign "$DEV_ID_CERT" --timestamp --options runtime \
  "$SPARKLE_B/Autoupdate"
codesign --force --sign "$DEV_ID_CERT" --timestamp --options runtime \
  "$APP/Contents/Frameworks/Sparkle.framework"

# Re-sign the main app with our entitlements (strips the debug-only
# com.apple.security.get-task-allow entitlement Xcode injects at build time).
echo "==> Re-signing FlicKey.app with clean entitlements"
codesign --force --sign "$DEV_ID_CERT" --timestamp --options runtime \
  --entitlements "$ROOT/FlicKey.entitlements" "$APP"

echo "==> Verifying the binary is clean"
if nm "$APP/Contents/MacOS/$APP_NAME" | grep -qiE "__llvm_prf|__profc|profile_runtime"; then
  echo "ERROR: profiling instrumentation present in Release binary" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
echo "    signature OK, no instrumentation"

echo "==> Packaging DMG (branded volume icon)"
mkdir -p "$DIST_DIR"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Volume icon: shown when the DMG is opened. It lives INSIDE the image, so it
# survives download — unlike a .dmg *file* icon, which macOS stores as metadata
# (resource fork) that GitHub strips on upload/download.
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

RW="$(mktemp -u).dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MNT="$(mktemp -d)"
hdiutil attach "$RW" -nobrowse -mountpoint "$MNT" >/dev/null
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MNT"            # mark the volume as having a custom icon
else
  echo "    (SetFile not found — skipping volume-icon bit)"
fi
hdiutil detach "$MNT" >/dev/null
rm -f "$DIST_DIR/$APP_NAME.dmg"
hdiutil convert "$RW" -format UDZO -o "$DIST_DIR/$APP_NAME.dmg" >/dev/null
rm -f "$RW"
hdiutil verify "$DIST_DIR/$APP_NAME.dmg" >/dev/null

echo "==> Notarizing DMG"
xcrun notarytool submit "$DIST_DIR/$APP_NAME.dmg" \
  --keychain-profile "flickey-notarize" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DIST_DIR/$APP_NAME.dmg"
xcrun stapler validate "$DIST_DIR/$APP_NAME.dmg"

echo "==> Done: $DIST_DIR/$APP_NAME.dmg"
shasum -a 256 "$DIST_DIR/$APP_NAME.dmg"
