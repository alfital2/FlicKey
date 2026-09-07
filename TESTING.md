# FlicKey — Testing

Three layers. Together they cover every aspect; each layer tests what it *can*.

| Layer | Command | Covers | Touches your Mac? |
|-------|---------|--------|-------------------|
| **Unit / replay** | `xcodebuild test -scheme FlicKey` (or just run in Xcode) | All the *logic*: layout conversion, per-site/per-conversation/per-app decisions, routing, parsing (incl. real captured Teams/browser traces), persistence, version compare, shortcut building, **focus-watcher gating (`FocusGate`), panel dismiss-restore (`PanelSession`), app-name matching (`AppRules.normalizedName`/`forcedSourceID`)** | No — headless, deterministic |
| **UI** | `scripts/run-ui-tests.sh` | The **Settings window** (all 4 tabs incl. Support/trial) + Apps add/remove + shortcut recorder & presets + menu-bar menu | Yes — controls the screen ~2 min |
| **Manual smoke** | this checklist | The **permission-gated functional flows** that can't be automated reliably (need granted Accessibility/Automation + real apps, and the global hotkey can't be double-registered) | Yes — you do it by hand |

### Run just one component

`scripts/test.sh <component>` runs only the tests for one area:

```
scripts/test.sh browser      # per-site memory + URL parsing + browser routing (headless)
scripts/test.sh browser-ui-firefox # LIVE opt-in Gecko integration test
scripts/test.sh teams        # Teams parser/store + Teams session replay (headless)
scripts/test.sh conversion   # wrong-layout fix logic (headless)
scripts/test.sh routing      # app routing + rules (headless)
scripts/test.sh apps         # app rules + Apps-tab add/remove UI      (controls screen)
scripts/test.sh shortcut     # shortcut logic + recorder UI            (controls screen)
scripts/test.sh support      # trial/license logic + Support-tab UI    (controls screen)
scripts/test.sh menubar      # status-item menu UI                     (controls screen)
scripts/test.sh settings     # Settings window UI                       (controls screen)
scripts/test.sh ui|unit|all  # whole UI scheme / all unit / everything
```
Also: `core`, `updates`, `input`. It prints a ✅/❌ summary and exits non-zero on failure.

**Experimental:** `scripts/test.sh browser-ui` and
`scripts/test.sh browser-ui-firefox` run *live* tests that drive Safari or Firefox
and assert the keyboard physically flips per site. They prove the end-to-end
pipelines work, but are **flaky** (browser session restore + address-bar timing)
and are **excluded from the default UI run** — use them as a starting point, not
a gate. The browser feature's *logic* is reliably covered by
`scripts/test.sh browser` + the manual checklist below.

> Why the functional flows are manual: they require the real Accessibility +
> Automation permissions, a real logged-in browser/Teams, and the system input
> source actually changing — none of which a test can grant/drive reliably. Their
> *logic* is already proven by the unit/replay tests; this checklist confirms the
> wiring to the real OS.

---

## Manual smoke checklist (~3 min)

Run after any change that touches input switching, AppleScript, AX, or the hotkey.

### 1. Fix wrong-layout text (the hotkey)
- [ ] In any text field, type gibberish from the wrong layout (e.g. `akuo`).
- [ ] Select it and press the conversion shortcut (default **⇧⇧** double-tap Shift; ⌥2 is a preset).
- [ ] ✅ It converts to the intended text (e.g. `שלום`) and the keyboard switches to that language.

### 2. Per-app switching
- [ ] Configure an app in **Settings → Apps** to a fixed language (e.g. Terminal → English).
- [ ] Focus that app.
- [ ] ✅ The menu-bar badge switches to that language.

### 3. Per-site memory (browser)
- [ ] In Safari/Chrome and Firefox/Zen, open an English site → set keyboard to English; open a Hebrew site → set Hebrew.
- [ ] Switch between the two tabs.
- [ ] ✅ The keyboard auto-flips to match each site.
- [ ] Scriptable browsers show a one-time “FlicKey wants to control …” prompt. Firefox/Zen must not show an Automation prompt; they use the Accessibility grant FlicKey already requires.
- [ ] With Firefox's `accessibility.force_disabled=1`, per-site switching quietly stops without a crash or stall.

### 4. Per-conversation memory (Teams)
- [ ] In **Settings → Apps**, Teams shows under **Chat apps** as “Auto (per-conversation)”.
- [ ] In Teams, set Hebrew in one chat and English in another; switch between them.
- [ ] ✅ The keyboard auto-flips per chat.
- [ ] Set Teams to a forced language in Settings → ✅ all chats use it (override wins); back to Auto → per-chat returns.

### 5. Non-activating panels (Ghostty quick terminal, Spotlight-style launchers)
> These grab the keyboard without becoming the frontmost app, so they bypass the
> normal app-activation path — covered by `FocusWatcher`. The *logic* is unit-tested
> (`FocusGate`, `PanelSession`); this confirms the wiring to the real OS. Needs an
> app whose panel is non-activating, e.g. Ghostty with
> `keybind = global:option+/=toggle_quick_terminal`.
- [ ] In **Settings → Apps**, force the panel's host app to a language (e.g. Ghostty → Hebrew); be in another app set to a different layout (e.g. Terminal → English).
- [ ] Summon the panel (e.g. **⌥/**) and type → ✅ the layout switches to the panel app's forced language (Hebrew).
- [ ] Dismiss the panel → ✅ the layout returns to the underlying app's language (English) without needing to click away and back.
- [ ] Open/close a few times rapidly → ✅ each summon forces, each dismiss restores; no stuck layout.
- [ ] (Known gap) Summon over a *browser/Teams* with live per-site memory: its layout is re-applied on the next tab/app activation rather than instantly on dismiss.

### 6. Settings & system integration
- [ ] **Settings → General → Launch FlicKey at login** ON → appears in System Settings ▸ General ▸ Login Items.
- [ ] **Check for Updates Now** → shows “up to date” (or an update) with a centered icon.
- [ ] **Settings → Shortcut → Record New Shortcut** → set a new combo → it triggers the fix; **Reset** restores ⌥2.
- [ ] Menu bar: badge reflects the current input language; **Settings…** opens the window; **Quit** quits.
