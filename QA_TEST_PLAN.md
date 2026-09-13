# FlicKey — Manual QA Test Plan

Run as a manual tester. Mark each: ✅ Pass / ❌ Fail / ⏭️ Skipped.
**Priority:** P1 = core/must-work · P2 = important · P3 = edge/polish.

**Test environment to note before starting:** macOS version, enabled input
sources (need at least English + Hebrew), conversion shortcut (default ⇧⇧),
whether macOS "Automatically switch to a document's input source" is OFF.

---

## A. Fix wrong-layout text (the conversion shortcut)

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| A1 | EN→HE fix | In any text field type `akuo`, then double-tap Shift | Text becomes `שלום`; keyboard switches to Hebrew | P1 |
| A2 | HE→EN fix | Type Hebrew-keyboard gibberish meant as English, then double-tap Shift | Becomes the intended English; keyboard → English | P1 |
| A3 | Nothing selected | Place cursor in a field with existing text and invoke the configured conversion trigger | Selects all, converts the whole field | P2 |
| A4 | Empty field | Focus an empty field and invoke the configured conversion trigger | "No text to convert" overlay; nothing crashes/changes | P2 |
| A5 | Clipboard restored | Copy `HELLO` to clipboard, do a conversion elsewhere, then paste | Clipboard still contains `HELLO` (conversion didn't clobber it) | P1 |
| A6 | No cascade on punctuation | Type a single ambiguous char (e.g. `w`), ⇧⇧, then ⇧⇧ again | Returns to original (`w`→`'`→`w`); does not keep mutating | P2 |
| A7 | Works with custom shortcut | Change shortcut (see F1), then repeat A1 with the new combo | Conversion fires on the new combo | P2 |
| A8 | Fix inside different apps | Repeat A1 in TextEdit, Notes, a browser field, a chat app | Works consistently across apps | P2 |

## B. Per-app input switching

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| B1 | Built-in forces language | Ensure Terminal is set to English (Settings→Apps); focus Terminal | Menu-bar badge → EN | P1 |
| B2 | Switch between two forced apps | Set App X→Hebrew, App Y→English; alternate focus | Badge follows each app's language | P1 |
| B3 | Unforced app leaves layout | Focus an app with no rule | Keyboard stays whatever it was (no change) | P1 |
| B4 | Change a rule takes effect | Change an app's language in Settings, focus it | New language applies immediately on next focus | P2 |
| B5 | Forced app overrides current | While on Hebrew, focus an English-forced app | Switches to English | P2 |
| B6 | FlicKey's own UI doesn't trigger | Open FlicKey Settings / menu | Does not count as "left app" / spurious switch | P3 |

## C. Per-site browser memory (the big one)

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| C1 | Learn + recall a site | On site A set Hebrew; leave; return to site A | Keyboard auto-switches to Hebrew on return | P1 |
| C2 | Two tabs, two languages | Tab1=English site (set EN), Tab2=Hebrew site (set HE); switch tabs back and forth | Keyboard auto-flips to match each site | P1 |
| C3 | Unknown site | Open a site never visited | Keyboard unchanged (no memory yet) | P1 |
| C4 | Overwrite a site | On a known site, manually change the language | New language remembered next visit | P2 |
| C5 | www normalization | Visit `www.site.com` then `site.com` | Treated as the same site (same memory) | P2 |
| C6 | Force a browser to one language | Settings→Apps: set the browser to English (not Auto) | All sites in that browser use English; per-site memory ignored | P2 |
| C7 | Back to Auto restores per-site | Set the browser back to "Auto (per-site)" | Per-site memory works again | P2 |
| C8 | Browser → other app → back | Switch from browser to a forced app, then back to browser | Per-site memory still applies on return | P2 |
| C9 | First-run Automation prompt | First time in a scriptable browser, approve "FlicKey wants to control Safari" | URL read works; per-site begins functioning | P1 |
| C10 | Multiple browsers | Repeat C1–C2 in Chrome and Firefox/Zen | Works independently per browser | P3 |
| C11 | Rapid tab switching | Quickly switch among 3 tabs several times | Ends on the correct language for the final tab; no crash | P2 |
| C12 | Gecko per-site memory | Repeat C1–C2 in Firefox | Keyboard flips per site; no Automation prompt | P1 |
| C13 | Zen | Repeat C1–C2 in Zen | Same as C12 | P1 |
| C14 | Zen split view | Put two sites side by side; click between panes | Follows the focused pane; if focus is unavailable, follows the largest pane | P2 |
| C15 | Ungoogled Chromium | Repeat C1–C2 in Chromium.app | Works through its published AppleScript tab vocabulary | P2 |
| C16 | Private window | Open a known site in a Firefox private window | Per-site memory applies | P2 |
| C17 | Gecko new tab | Press ⌘T in Firefox/Zen | New-tab preference applies instead of the prior site's layout | P1 |
| C18 | Gecko a11y disabled | Set `accessibility.force_disabled=1`, restart Firefox | No crash, hang, or beachball; per-site switching quietly pauses | P2 |
| C19 | Discovery churn | Install/remove and launch a browser while FlicKey runs | Settings → Browsers updates on launch/mount or within the cache TTL | P2 |
| C20 | Legacy custom entry | Upgrade with Zen saved as a custom app | Zen appears under Browsers as Auto, not as a forced app | P1 |
| C21 | Gecko performance | Firefox with ~50 tabs; rapidly switch tabs | No beachball; warm URL reads stay cached | P2 |
| C22 | Mixed engines | Safari → Firefox → Chromium, each on a different site | Each uses its discovered reader with no cross-talk | P2 |

## D. Per-conversation memory (Microsoft Teams)

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| D1 | Teams listed correctly | Settings→Apps | Teams appears under "Chat apps" as "Auto (per-conversation)" | P1 |
| D2 | Learn + recall a chat | In chat A set Hebrew; open chat B; return to chat A | Keyboard restores Hebrew for chat A | P1 |
| D3 | Two chats, two languages | Chat A=Hebrew, Chat B=English; switch between | Keyboard auto-flips per chat | P1 |
| D4 | Non-chat view | Open Activity / Calendar / chat list | No per-conversation switch (keyboard unchanged) | P2 |
| D5 | Force Teams to one language | Settings→Apps: set Teams→English | All Teams chats use English (override wins) | P2 |
| D6 | Back to Auto | Set Teams back to "Auto (per-conversation)" | Per-chat memory works again | P2 |
| D7 | Notification banner reply | Reply to a message from the macOS notification banner | Known limitation: NOT captured (uses current global layout) | P3 |

## E. Apps list — add / configure / remove (full lifecycle)

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| E1 | **Full lifecycle** | (1) Settings→Apps, type an app name, add it. (2) Set it to Hebrew. (3) Focus that app → badge HE. (4) Focus another app and back → still HE. (5) Right-click row → Remove. (6) Focus the app again. | (1) Row appears. (3)(4) Switches to Hebrew. (5) Row removed. (6) No longer forces a language. | P1 |
| E2 | Add by name | Type a known app name, press Enter / pick suggestion | App added with its real icon | P1 |
| E3 | Add by Browse (+) | Click +, choose an app in Finder | App added | P2 |
| E4 | Live suggestions | Type ≥3 chars of an app name | Matching apps appear in a dropdown | P3 |
| E5 | Unknown name | Type a name that doesn't exist, Enter | "No app named …" message; nothing added | P2 |
| E6 | Duplicate add | Add an app already in the list | "… is already listed"; no duplicate row | P2 |
| E7 | Remove built-in | Right-click a built-in app → Remove | Hidden from list | P2 |
| E8 | Re-add removed built-in | Add the same built-in back by name | Restored (not duplicated) | P2 |
| E9 | List grouping | Inspect the list | Normal apps, then "Chat apps" (Teams), then "Browsers" sections | P3 |
| E10 | Per-app popup options | Open the popup on a normal vs browser vs Teams row | Normal: languages only. Browser: + "Auto (per-site)". Teams: + "Auto (per-conversation)" | P2 |

## F. Conversion shortcut configuration

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| F1 | Record new shortcut | Settings→Shortcut→Record New Shortcut, press ⌃⌥F | Shows ⌃⌥F; pressing it now triggers the fix | P1 |
| F2 | Old shortcut stops | After F1, double-tap Shift | ⇧⇧ no longer triggers the fix | P2 |
| F3 | Reset to default | Click "Reset to ⇧⇧" | Shortcut returns to ⇧⇧; double-Shift works again | P2 |
| F4 | Modifier required | Start recording, press a bare key (no modifier) | Rejected with a hint; not saved | P2 |
| F5 | Esc cancels | Start recording, press Esc | Recording stops; shortcut unchanged | P3 |
| F6 | Persists across restart | Set a custom shortcut, quit & relaunch FlicKey | Custom shortcut still active | P2 |

## G. Settings — General (startup, updates)

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| G1 | Launch at login ON | Toggle ON; check System Settings ▸ General ▸ Login Items | FlicKey listed as a login item | P1 |
| G2 | Launch at login OFF | Toggle OFF; recheck Login Items | FlicKey removed | P2 |
| G3 | Auto-update toggle persists | Toggle "Automatically check for updates", reopen Settings | State preserved | P2 |
| G4 | Check now — up to date | Click "Check for Updates Now" while on latest | Centered dialog: "You're up to date · FlicKey X.Y.Z" | P1 |
| G5 | Check now — update available | (If a newer release exists) click Check Now | Centered dialog offers Download → opens release page | P2 |
| G6 | Version label | Read the version at bottom of General | Matches the installed version | P3 |

## H. Menu bar & window chrome

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| H1 | Live badge | Manually switch input language a few times | Menu-bar badge updates to EN/HE/… live | P1 |
| H2 | Menu items | Click the menu-bar icon | Shows status line, Settings…, Quit | P2 |
| H3 | Settings ⌘, | With menu open press ⌘, (or click Settings…) | Settings window opens | P2 |
| H4 | Window tabs resize/title | Open Settings, switch General→Apps→Shortcut | Window resizes per tab; title shows the tab name | P3 |
| H5 | ⌘W closes | In Settings press ⌘W | Window closes | P2 |
| H6 | Quit | Menu → Quit (or ⌘Q context) | App quits; badge disappears | P2 |

## I. Permissions & first launch

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| I1 | First launch (Gatekeeper) | Fresh install, double-click | Blocked (not notarized); right-click → Open works | P1 |
| I2 | Accessibility prompt | First run | Prompts for Accessibility; granting enables switching + hotkey | P1 |
| I3 | Without Accessibility | Deny/disable Accessibility | App doesn't crash; AX features simply inactive | P2 |
| I4 | Grant persists across update | Update to a new build (same signing) | Accessibility/Automation grants remain | P2 |

## J. Edge cases & regressions

| ID | Scenario | Steps | Expected | Pri |
|----|----------|-------|----------|-----|
| J1 | OS auto-switch warning | Turn ON macOS "Automatically switch to a document's input source" | Menu shows ⚠️ warning; clicking opens Keyboard settings + guide | P2 |
| J2 | Handoff no stale write | Browser (site=HE) → Teams (chat=EN) → a forced app → back; change a layout in each | No layout saved under the wrong site/chat | P2 |
| J3 | Override precedence | Force a browser/Teams to English while it has per-site/chat memory | Forced English wins everywhere for that app | P2 |
| J4 | 3+ enabled layouts | Enable English+Hebrew+Russian | Conversion uses the first two (documented limit); no crash | P3 |
| J5 | Weird app name | Focus an app with an empty/unicode localized name | No crash; handled gracefully | P3 |
| J6 | Rapid everything | Stress: switch apps/tabs/chats quickly for ~30s | No crash, no stuck state; final language correct | P2 |
| J7 | Clipboard managers | With Maccy/Paste running, do a conversion | The transient converted text is not captured (Concealed/Transient flags) | P3 |
| J8 | Non-English Teams UI | (If available) Teams in another UI language | Per-conversation no-ops gracefully (English "Chat" label only) | P3 |




• Yes—you remembered correctly. The repository contains:

  - Tests/: 525 automated unit/replay tests
  - UITests/: Settings, app switching, auto-fix, Firefox, Safari, Teams, Spotlight, menu bar, etc.
  - scripts/test.sh: test runner

  Important: the DMG alone cannot run these tests. The VM needs Xcode plus the source checkout at commit 72079c3. The automated UI tests build their own test-enabled
  app; the signed DMG still needs the separate manual checklist.

  From the source directory inside the VM:

  # Complete unit suite
  scripts/test.sh unit

  # Standard UI suite
  # Takes control of mouse and keyboard
  scripts/test.sh ui

  # Live Firefox integration
  scripts/test.sh browser-ui-firefox

  # Live auto-fix in TextEdit
  scripts/test.sh fix-ui

  # App routing and Apps-tab tests
  scripts/test.sh apps

  # Optional live Teams integration
  scripts/test.sh teams-ui

  Or:

  scripts/test.sh all

  all runs unit tests plus the standard UI suite, but deliberately excludes the live Firefox/Safari and Teams integrations because those are environment-dependent. Run
  those separately afterward.

  The complete VM test sequence should therefore be:

  scripts/test.sh all
  scripts/test.sh browser-ui-firefox
  scripts/test.sh fix-ui
  scripts/test.sh teams-ui
