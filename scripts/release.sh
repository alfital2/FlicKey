#!/usr/bin/env bash
#
# release.sh — cut a Sparkle release: build, sign, and produce the appcast feed.
#
# Outputs in dist/:
#   FlicKey.dmg   — for first-time installs (drag to Applications)
#   FlicKey.zip   — the Sparkle update archive (what in-app auto-update downloads)
#   appcast.xml   — the Sparkle feed (also copied into the flickey-app repo,
#                   which GitHub Pages serves at https://flickey.site/appcast.xml)
#
# To publish (the script prints these at the end):
#   1) gh release create vX.Y.Z dist/FlicKey.dmg dist/FlicKey.zip \
#        --repo alfital2/FlicKey -t "vX.Y.Z"
#   2) in the flickey-app repo: commit & push the updated appcast.xml
#
# The EdDSA private key lives in your login Keychain (created once by
# generate_keys). BACK IT UP — without it you cannot sign future updates that
# existing installs will accept:
#   generate_keys -x exports a backup; keep it OUTSIDE the repo (default:\n#   ~/Library/Application Support/FlicKey-signing/, override with SPARKLE_KEY_FILE)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TOOLS="$ROOT/scripts/sparkle-tools/bin"
SITE_REPO="${SITE_REPO:-$ROOT/../flickey-app}"
DL_BASE="https://github.com/alfital2/FlicKey/releases/download"

VERSION="$(grep -m1 'MARKETING_VERSION'      project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
BUILD="$(  grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
MINOS="$(  grep -m1 'macOS:'                  project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
TAG="v$VERSION"
echo "==> Releasing FlicKey $VERSION (build $BUILD, $TAG)"

# Sparkle CLI tools — auto-download if missing.
if [ ! -x "$TOOLS/sign_update" ]; then
  echo "==> Fetching Sparkle tools"
  STAG="$(gh release view --repo sparkle-project/Sparkle --json tagName -q .tagName)"
  URL="$(gh release view "$STAG" --repo sparkle-project/Sparkle --json assets \
        -q '.assets[]|select(.name|test("Sparkle-.*\\.tar\\.xz$")).url' | head -1)"
  mkdir -p "$ROOT/scripts/sparkle-tools"
  curl -sL "$URL" | tar -xJ -C "$ROOT/scripts/sparkle-tools" bin
fi

# Build + DMG (runs tests, builds Release via -target, verifies signature).
scripts/build-dmg.sh

APP="$ROOT/build/Release/FlicKey.app"
mkdir -p "$ROOT/dist"

echo "==> Zipping the Sparkle update archive"
rm -f "$ROOT/dist/FlicKey.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/FlicKey.zip"

echo "==> Signing the update (EdDSA)"
# Prefer the exported key file (works non-interactively / in CI). Fall back to
# the login Keychain if the backup file isn't present.
KEYFILE="${SPARKLE_KEY_FILE:-$HOME/Library/Application Support/FlicKey-signing/flickey-sparkle-key.txt}"
if [ -f "$KEYFILE" ]; then
  SIGOUT="$("$TOOLS/sign_update" --ed-key-file "$KEYFILE" "$ROOT/dist/FlicKey.zip")"
else
  SIGOUT="$("$TOOLS/sign_update" "$ROOT/dist/FlicKey.zip")"
fi
echo "    $SIGOUT"   # -> sparkle:edSignature="..." length="..."

PUBDATE="$(LC_ALL=en_US.UTF-8 date -u '+%a, %d %b %Y %H:%M:%S +0000')"

echo "==> Writing appcast.xml"
cat > "$ROOT/dist/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>FlicKey</title>
    <link>https://flickey.site/appcast.xml</link>
    <description>In-app updates for FlicKey.</description>
    <language>en</language>
    <item>
      <title>FlicKey $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
      <link>https://flickey.site</link>
      <enclosure url="$DL_BASE/$TAG/FlicKey.zip" type="application/octet-stream" $SIGOUT />
    </item>
  </channel>
</rss>
XML

if [ -d "$SITE_REPO" ]; then
  cp "$ROOT/dist/appcast.xml" "$SITE_REPO/appcast.xml"
  echo "    copied to $SITE_REPO/appcast.xml"
fi

cat <<DONE

==> Built:
    dist/FlicKey.dmg   (first-time install)
    dist/FlicKey.zip   (Sparkle update)
    dist/appcast.xml   (feed)

Publish:
  1) gh release create $TAG dist/FlicKey.dmg dist/FlicKey.zip \\
       --repo alfital2/FlicKey -t "$TAG" -n "FlicKey $VERSION"
  2) cd $SITE_REPO && git add appcast.xml && git commit -m "appcast: $VERSION" && git push
DONE
