#!/usr/bin/env bash
# Run inside the dedicated Tart guest after its first boot.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

[[ "$(sysctl -n hw.model)" == VirtualMac* ]] || {
    echo "This setup must run inside a macOS VM." >&2; exit 1;
}
[[ "$(id -un)" == admin ]] || exit 1
test -d /Applications/Xcode.app/Contents/Developer
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
sudo DevToolsSecurity -enable
if ! command -v xcodegen >/dev/null; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
for cask in firefox microsoft-teams; do
    HOMEBREW_NO_AUTO_UPDATE=1 brew list --cask "$cask" >/dev/null 2>&1 \
        || HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask "$cask"
done
# These are disposable test-VM installs fetched by Homebrew. Clear their cask
# quarantine metadata during provisioning so Gatekeeper's first-launch sheet
# cannot block an unattended XCTest run.
sudo xattr -dr com.apple.quarantine /Applications/Firefox.app
sudo xattr -dr com.apple.quarantine '/Applications/Microsoft Teams.app'
sudo mkdir -p /Applications/Firefox.app/Contents/Resources/distribution
sudo cp '/Volumes/My Shared Files/source/scripts/firefox-test-policies.json' \
    /Applications/Firefox.app/Contents/Resources/distribution/policies.json

# Keep the guest desktop available for XCTest; these settings affect only the VM.
sudo pmset -a sleep 0 displaysleep 0
defaults -currentHost write com.apple.screensaver idleTime -int 0
swift '/Volumes/My Shared Files/source/scripts/tart-input-sources.swift'

if ! csrutil status 2>/dev/null | grep -q 'disabled'; then
    echo 'SIP is enabled; Accessibility grants require manual approval.' >&2
    exit 1
fi
touch /Users/admin/.flickey-test-vm
xcodebuild -version
echo 'Guest tools installed. UI-test grants refresh automatically after each build.'
