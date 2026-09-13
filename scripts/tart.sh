#!/usr/bin/env bash
# Isolated macOS testing. All xcodebuild/test commands execute inside the VM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TART="${FLICKEY_TART_BIN:-/Applications/tart.app/Contents/MacOS/tart}"
VM="flickey-ui"
JOB="com.talalfi.flickey-test-vm"
STATE="$ROOT/build/tart"
VM_LOG="/private/tmp/flickey-tart-vm.log"
GUEST="/Users/admin/flickey-oss"
mkdir -p "$STATE/source" "$STATE/results"

stage() {
    # Share only build inputs, never host credentials or development-agent settings.
    for directory in Sources Resources Tests UITests scripts; do
        mkdir -p "$STATE/source/$directory"
        rsync -ac --delete "$ROOT/$directory/" "$STATE/source/$directory/"
    done
    cp "$ROOT/project.yml" "$ROOT/FlicKey.entitlements" "$ROOT/FlicKeyUITests.entitlements" "$STATE/source/"
}

guest() { "$TART" exec "$VM" "$@"; }

sync_source() {
    stage
    # VirtioFS can briefly expose stale size metadata while a mounted file is
    # replaced. Stream a snapshot through tart exec, then rsync locally in the
    # guest so a test can never compile a half-updated source file.
    guest /bin/bash -c 'rm -rf /private/tmp/flickey-source-sync; mkdir -p /private/tmp/flickey-source-sync /Users/admin/flickey-oss'
    tar -C "$ROOT" -cf - Sources Resources Tests UITests scripts project.yml FlicKey.entitlements FlicKeyUITests.entitlements \
        | "$TART" exec -i "$VM" tar -xpf - -C /private/tmp/flickey-source-sync
    guest /usr/bin/rsync -a --delete --exclude build/ --exclude FlicKey.xcodeproj/ \
        /private/tmp/flickey-source-sync/ /Users/admin/flickey-oss/
}

case "${1:-status}" in
    start|start-visible)
        mode="$1"
        stage
        if "$TART" list | grep -E "flickey-ui.*running" >/dev/null; then
            echo "VM is already running."
            exit 0
        fi
        launchctl remove "$JOB" 2>/dev/null || true
        tart_args=(run "$VM" --no-audio --no-clipboard
            --dir="source:$STATE/source:ro"
            --dir="results:$STATE/results")
        [[ "$mode" == start ]] && tart_args+=(--no-graphics)
        # Audio and clipboard stay isolated in both visible and background modes.
        launchctl submit -l "$JOB" -o "$VM_LOG" -e "$VM_LOG" -- \
            "$TART" "${tart_args[@]}"
        launchctl kickstart "gui/$(id -u)/$JOB"
        if [[ "$mode" == start-visible ]]; then
            echo "VM starting in a visible Tart window; move it to the Space you prefer."
        else
            echo "VM starting; log: $VM_LOG"
        fi
        ;;
    stop)
        "$TART" stop "$VM"
        launchctl remove "$JOB" 2>/dev/null || true
        ;;
    status) "$TART" list ;;
    sync) sync_source ;;
    setup)
        stage
        if ! guest /usr/bin/codesign --verify --deep --strict /Applications/Xcode.app; then
            tar -C /Applications -cf - Xcode.app | "$TART" exec -i "$VM" sudo tar -xpf - -C /Applications
        fi
        guest /bin/bash '/Volumes/My Shared Files/source/scripts/tart-guest-setup.sh'
        ;;
    exec) shift; guest "$@" ;;
    smoke|unit|ui|all|fix-ui|spotlight-ui|browser-ui|browser-ui-firefox|teams-ui)
        action="$1"
        sync_source
        # The guest name and marker prevent accidentally running this on the host.
        guest /bin/bash -c 'test -f /Users/admin/.flickey-test-vm && test "$(stat -f %Su /dev/console)" = admin'
        guest_environment=(/usr/bin/env
            "PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            "FLICKEY_TEST_DERIVED_DATA=$GUEST/build/DerivedData"
            "FLICKEY_VM_RESULTS=/Volumes/My Shared Files/results"
            "FLICKEY_REQUIRE_NO_UI_SKIPS=1")
        # Xcode strips TEST_RUNNER_ when forwarding variables to the XCTest
        # process. Optional host values let the live Teams story target any two
        # harmless chats without baking personal contact names into the repo.
        if [[ "$action" == teams-ui ]]; then
            [[ -n "${TEAMS_CHAT_A:-}" ]] && guest_environment+=("TEST_RUNNER_TEAMS_CHAT_A=$TEAMS_CHAT_A")
            [[ -n "${TEAMS_CHAT_B:-}" ]] && guest_environment+=("TEST_RUNNER_TEAMS_CHAT_B=$TEAMS_CHAT_B")
        fi
        guest "${guest_environment[@]}" /bin/bash -c "cd $GUEST; scripts/test-vm.sh $action"
        ;;
    *) echo "Usage: scripts/tart.sh start|start-visible|stop|status|setup|sync|smoke|unit|ui|all|fix-ui|spotlight-ui|browser-ui|browser-ui-firefox|teams-ui|exec <command...>" >&2; exit 2 ;;
esac
