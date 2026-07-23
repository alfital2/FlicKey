#!/usr/bin/env bash
#
# test.sh — run a specific section of the test suite.
#
# Usage:  scripts/test.sh <component>
#
# Components:
#   browser      per-site browser memory + URL parsing + browser routing
#   browser-ui   LIVE: drives real Safari, asserts the keyboard flips per site
#                (EXPERIMENTAL/FLAKY — Safari session-restore + address-bar timing;
#                excluded from the default UI run; proves the feature but is not
#                reliable as a gate. The feature's logic is covered by 'browser'.)
#   teams        Teams per-conversation parser/store + Teams session replay
#   teams-ui     LIVE: drives real Microsoft Teams, asserts the keyboard
#                follows the open chat (EXPERIMENTAL/FLAKY — needs Teams logged
#                in with a chat; excluded from the default UI run)
#   conversion   wrong-layout fix (layout conversion / round-trips)
#   fix-ui       LIVE: types gibberish in TextEdit, ⇧⇧, asserts it converts
#                (part of the default UI run too)
#   core         the shared decision engine
#   routing      app-activation routing + app rules
#   apps         app rules + the Apps-tab add/remove UI  (UI → controls screen)
#   shortcut     shortcut building/persistence + recorder UI  (UI → controls screen)
#   updates      update version check
#   input        input source catalog/manager
#   support      trial/license logic + the Support tab UI  (UI → controls screen)
#   menubar      the status-item menu  (UI → controls screen)
#   settings     the Settings window UI  (UI → controls screen)
#   ui           ALL UI tests  (UI → controls screen)
#   unit         ALL headless unit/replay tests
#   all          everything (unit + UI)
#
# Unit sections are headless. Sections marked "UI" drive the real app and take
# over the screen for ~30s.
set -uo pipefail
cd "$(dirname "$0")/.."

COMPONENT="${1:-}"
if [ -z "$COMPONENT" ]; then
  sed -n '5,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

UNIT=()   # -only-testing args under the FlicKey (unit) scheme
UI=()     # -only-testing args under the FlicKeyUITests scheme
t() { UNIT+=("-only-testing:FlicKeyTests/$1"); }
u() { UI+=("-only-testing:FlicKeyUITests/$1"); }

WHOLE_UNIT=0   # run the entire unit scheme
WHOLE_UI=0     # run the entire UI scheme

case "$COMPONENT" in
  browser)
    t SiteMemoryStoreTests; t BrowserURLReaderTests
    t SessionReplayTests/testBrowserSession_perSiteRecallAndUnreadableUrlKeepsPriorSite
    t AppRoutingTests/testBrowserAutoRoutesToBrowser ;;
  browser-ui)
    u BrowserIntegrationUITests ;;   # LIVE: drives Safari, controls screen
  teams)
    t TeamsConversationProviderTests; t ContextMemoryStoreTests
    t SessionReplayTests/testRealTeamsSession_flapAndNonConversationViewsDoNotCorruptMemory
    t SessionReplayTests/testTeamsFastSwitch_staleInputChangeIsNotSavedUnderTheNewChat ;;
  teams-ui)
    u TeamsIntegrationUITests ;;   # LIVE: drives real Teams, controls screen
  conversion|fix)
    t ConversionEngineTests; t LayoutConverterTests; t RoundTripTests ;;
  fix-ui)
    u HotkeyConversionUITests ;;   # LIVE: the ⇧⇧ fix in TextEdit (controls screen)
  core)
    t ConversationMemoryCoreTests ;;
  routing)
    t AppRoutingTests; t AppRulesTests; t RulesStoreTests; t InputRuleTests ;;
  apps)
    t AppRulesTests; t RulesStoreTests; t AppFinderTests; t AppRoutingTests
    u FunctionalUITests/testAddThenRemoveAnApp
    u FunctionalUITests/testAddingDuplicateIsRejected
    u AppSwitchingUITests ;;           # live per-app hop (forced + preserve)
  shortcut)
    t ShortcutTests
    u FunctionalUITests/testRecordThenResetShortcut
    u FunctionalUITests/testBareKeyDuringRecordingIsRejected ;;
  updates)
    t UpdateCheckerTests ;;
  input)
    t InputSourceTests ;;
  support)
    t TrialLogicTests; t LemonSqueezyTests
    u SupportUITests ;;                # trial/license logic + Support-tab UI
  menubar)
    u MenuBarUITests ;;                # status-item menu (UI → controls screen)
  settings)
    WHOLE_UI=1; u SettingsUITests ;;   # only the Settings class
  ui)
    WHOLE_UI=1 ;;
  unit)
    WHOLE_UNIT=1 ;;
  all)
    WHOLE_UNIT=1; WHOLE_UI=1 ;;
  *)
    echo "Unknown component: '$COMPONENT'"
    echo "Try: browser teams conversion core routing apps shortcut updates input support menubar settings ui unit all"
    exit 2 ;;
esac

xcodegen generate >/dev/null 2>&1
mkdir -p build
TRANSCRIPT="build/test-transcript.txt"
: > "$TRANSCRIPT"   # fresh each run

overall=0
filter='Test Case .* (passed|failed)|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|error:|STEP ▸'

run() {   # run <scheme> <args...>
  local scheme="$1"; shift
  local bundle="build/${scheme}.xcresult"; rm -rf "$bundle"
  # Show pass/fail + the live "STEP ▸" narration each test emits (cleaned to a
  # plain "▸ doing X"); also save it to the transcript file + an .xcresult bundle.
  xcodebuild test -project FlicKey.xcodeproj -scheme "$scheme" -destination 'platform=macOS' \
    -resultBundlePath "$bundle" "$@" \
    2>&1 | grep -iE "$filter" | sed -E 's/.*STEP ▸ /   ▸ /' | tee -a "$TRANSCRIPT"
  local s=${PIPESTATUS[0]}
  [ "$s" -ne 0 ] && overall=1
  return 0
}

# Unit portion (headless)
if [ "$WHOLE_UNIT" -eq 1 ]; then
  echo "▶ unit (all)"; run FlicKey
elif [ ${#UNIT[@]} -gt 0 ]; then
  echo "▶ unit: ${UNIT[*]#-only-testing:FlicKeyTests/}"; run FlicKey "${UNIT[@]}"
fi

# UI portion (controls the screen)
if [ "$WHOLE_UI" -eq 1 ] || [ ${#UI[@]} -gt 0 ]; then
  echo
  echo "⚠️  UI tests will CONTROL THE SCREEN for ~30s. Don't touch mouse/keyboard."
  for i in 5 4 3 2 1; do printf "\r    starting in %ss…" "$i"; sleep 1; done; echo
  if [ ${#UI[@]} -gt 0 ]; then
    echo "▶ ui: ${UI[*]#-only-testing:FlicKeyUITests/}"; run FlicKeyUITests "${UI[@]}"
  else
    # The live Safari/Teams tests are opt-in (flaky) — only via 'browser-ui' /
    # 'teams-ui', never the whole-UI run.
    echo "▶ ui (all, excl. live browser/Teams)"
    run FlicKeyUITests -skip-testing:FlicKeyUITests/BrowserIntegrationUITests \
                       -skip-testing:FlicKeyUITests/TeamsIntegrationUITests
  fi
fi

echo "──────────────────────────────────────────────"
[ "$overall" -eq 0 ] && echo "✅ '$COMPONENT' tests PASSED" || echo "❌ '$COMPONENT' tests FAILED"
echo "   Transcript:  $TRANSCRIPT   (open with: cat $TRANSCRIPT)"
echo "   Xcode report: build/*.xcresult   (open with: open build/FlicKeyUITests.xcresult)"
echo "──────────────────────────────────────────────"
exit "$overall"
