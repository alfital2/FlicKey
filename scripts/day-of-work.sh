#!/bin/bash
# Visible, live "day of work" driver — the screen-driving robot.
#
# Focus: the per-conversation / per-site memory engine (ConversationMemoryCore),
# which is the shared engine behind the Teams inconsistency bug. It hammers that
# engine through the BROWSER (reliably scriptable) and VERIFIES the input source
# switches to the remembered layout on every site change — directly catching the
# "didn't switch / switched wrong / saved under the wrong key" class. It also does
# TextEdit + manual double-Shift conversion, and observes Teams live for the
# AX-specific failures (stuck token / unreadable spikes).
#
# It will control Safari / TextEdit / Teams for the duration — don't use the Mac
# while it runs. Ctrl-C to stop early.
#
# Usage: scripts/day-of-work.sh [seconds]        # default 600 (~10 min)
set -uo pipefail
cd "$(dirname "$0")/.."

DUR="${1:-600}"
HELPER="/tmp/flickey-isrc-helper"
TRAIL="/tmp/flickey-dayofwork-trail.log"
REPORT="/tmp/flickey-dayofwork-report.txt"
APP="$(cat /tmp/flickey_app_path.txt 2>/dev/null)"
A="com.apple.keylayout.ABC"
B="com.apple.keylayout.Hebrew-PC"
SITES=(example.com wikipedia.org apple.com mozilla.org github.com)

ACTIONS="/tmp/flickey-dayofwork-actions.log"
: > "$REPORT"; : > "$ACTIONS"
anomalies=0
# Timestamped so each action can be lined up against the diagnostic trail
# (both use wall-clock HH:MM:SS.mmm) to see which site FlicKey was on when a
# save fired — the difference between a real detection-lag race and a driver hiccup.
stamp() { date '+%H:%M:%S.%3N' 2>/dev/null || date '+%H:%M:%S'; }
note() { echo "  ⚠ $*" | tee -a "$REPORT"; echo "$(stamp) ANOMALY $*" >> "$ACTIONS"; anomalies=$((anomalies + 1)); }
say()  { printf '[%s] %s\n' "$(stamp)" "$*"; echo "$(stamp) $*" >> "$ACTIONS"; }

# --- setup ---------------------------------------------------------------
swiftc scripts/day-of-work-helper.swift -o "$HELPER" || { echo "helper compile failed"; exit 1; }
cur() { "$HELPER" current; }
setlayout() { "$HELPER" set "$1"; sleep 0.4; }
# The layout FlicKey has stored for a domain (empty if none).
saved_for() { defaults read com.talalfi.FlicKey siteInputMemory 2>/dev/null | awk -F'"' -v d="$1" '$2==d{print $4}'; }

# Run osascript with a hard timeout so a permission dialog / stuck app can never
# freeze the whole run (macOS has no `timeout`). The FIRST few calls will prompt
# "Terminal wants to control Safari / System Events" — approve them once.
osa() {
  osascript "$@" >/dev/null 2>&1 &
  local p=$!
  ( sleep 8; kill -9 "$p" 2>/dev/null ) & local guard=$!
  wait "$p" 2>/dev/null
  kill "$guard" 2>/dev/null
}

defaults write com.talalfi.FlicKey diagRecordEnabled -bool YES   # trail → unified log
pgrep -x FlicKey >/dev/null || { [ -n "$APP" ] && open "$APP"; sleep 3; }

rm -f "$TRAIL"
log stream --predicate 'subsystem == "com.talalfi.FlicKey" AND category == "event"' --style compact > "$TRAIL" 2>&1 &
STREAM_PID=$!
cleanup() { kill "$STREAM_PID" 2>/dev/null; }
trap cleanup EXIT

open -a Safari 2>/dev/null; sleep 2

navigate() {  # $1 = domain
  osa -e 'tell application "Safari"' \
      -e 'activate' \
      -e 'if (count of windows) = 0 then make new document' \
      -e "set URL of front document to \"https://$1\"" \
      -e 'end tell'
  sleep 2.5   # let the tab settle + FlicKey poll/apply
}

type_and_convert() {  # TextEdit: type gibberish, double-Shift, check it changed
  osa -e 'tell application "TextEdit"' \
      -e 'activate' \
      -e 'if (count of documents) = 0 then make new document' \
      -e 'set text of front document to ""' \
      -e 'end tell'
  sleep 1
  osa -e 'tell application "System Events" to keystroke "akuo"'
  sleep 0.4
  osa -e 'tell application "System Events" to key code 56' -e 'delay 0.08' -e 'tell application "System Events" to key code 56'
  sleep 1.2
  local txt; txt="$(osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null)"
  [ "$txt" = "akuo" ] && note "TextEdit manual ⇧⇧: 'akuo' did NOT convert (still '$txt')"
}

# --- expected-memory model ----------------------------------------------
# Indexed array parallel to SITES (macOS bash 3.2 has no associative arrays):
# EXPECT[i] is the layout last set for SITES[i].
EXPECT=()
sites_set=0

say "starting ~${DUR}s day-of-work; controlling Safari/TextEdit/Teams. Report → $REPORT"
END=$(( $(date +%s) + DUR ))
step=0
while [ "$(date +%s)" -lt "$END" ]; do
  step=$((step + 1))
  roll=$(( RANDOM % 100 ))

  if [ "$roll" -lt 55 ]; then
    # Browser: navigate + verify the remembered layout was applied.
    si=$(( RANDOM % ${#SITES[@]} ))
    site="${SITES[$si]}"
    say "navigate → $site [step $step]"
    navigate "$site"
    exp="${EXPECT[$si]:-}"
    if [ -n "$exp" ]; then
      got="$(cur)"
      [ "$got" != "$exp" ] && { sleep 1.2; got="$(cur)"; }   # tolerate a slow apply, re-read once
      if [ "$got" != "$exp" ]; then
        note "site $site: remembered $exp but layout is $got (memory NOT applied) [step $step]"
      fi
    fi
    # ~1/3 of the time the 'user' sets a language for this site — always to a
    # DIFFERENT layout so a real change fires, then VERIFY FlicKey saved it for
    # THIS site (a save landing elsewhere is the genuine race we want to catch).
    if [ $(( RANDOM % 3 )) -eq 0 ]; then
      [ "$(cur)" = "$A" ] && new="$B" || new="$A"
      setlayout "$new"; sleep 1.3
      landed="$(saved_for "$site")"
      if [ "$landed" = "$new" ]; then
        [ -z "${EXPECT[$si]:-}" ] && sites_set=$(( sites_set + 1 ))
        EXPECT[$si]="$new"
        say "set $site → $(basename "$new") ✓saved"
      else
        note "site $site: set $(basename "$new") but FlicKey stored '$landed' (save race / wrong key) [step $step]"
      fi
    fi

  elif [ "$roll" -lt 75 ]; then
    type_and_convert

  elif [ "$roll" -lt 90 ]; then
    osa -e 'tell application "Microsoft Teams" to activate'
    osa -e 'tell application "Microsoft Teams (work or school)" to activate'
    sleep 2   # observe: the trail records conversation tokens / unreadable

  else
    osa -e 'tell application "Finder" to activate'; sleep 1
  fi
done

sleep 1
# --- analysis ------------------------------------------------------------
{
  echo ""
  echo "======== day-of-work report ($(date '+%H:%M:%S')) ========"
  echo "steps: $step   sites set: $sites_set"
  echo ""
  echo "-- conversation/site trail summary --"
  echo "site changes:        $(grep -c 'site → '            "$TRAIL" 2>/dev/null || echo 0)"
  echo "conversation resolves:$(grep -c 'conversation\['     "$TRAIL" 2>/dev/null || echo 0)"
  echo "memory applied:      $(grep -c 'memory applied'     "$TRAIL" 2>/dev/null || echo 0)"
  echo "memory saved:        $(grep -c 'memory saved'       "$TRAIL" 2>/dev/null || echo 0)"
  echo "Teams UNREADABLE:    $(grep -c 'unreadable'         "$TRAIL" 2>/dev/null || echo 0)   (Teams AX read failures)"
  echo ""
  # Invariant checks from the trail itself:
  if grep -q 'saved with no active' "$TRAIL" 2>/dev/null; then
    echo "  ⚠ trail shows a save with no active conversation (stale-key bug)"; anomalies=$((anomalies+1))
  fi
  ur=$(grep -c 'unreadable' "$TRAIL" 2>/dev/null || echo 0)
  [ "$ur" -gt 5 ] && { echo "  ⚠ high Teams-unreadable count ($ur): AX tree detection is struggling"; anomalies=$((anomalies+1)); }
  echo ""
  echo "VERIFICATION ANOMALIES: $anomalies"
  [ "$anomalies" -eq 0 ] && echo "✅ no memory-apply mismatches or trail anomalies detected" \
                         || echo "❌ see the ⚠ lines above — reproduce with the same sites"
} | tee -a "$REPORT"
echo ""
echo "full trail: $TRAIL   report: $REPORT"
