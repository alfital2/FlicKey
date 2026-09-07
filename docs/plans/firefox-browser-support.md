# Plan — Support tabs in Firefox-based (and unrecognized) browsers

Tracks GitHub issue [#1](https://github.com/alfital2/FlicKey/issues/1) (reporter: @abjugard, uses
[Zen](https://zen-browser.app/); also reports ungoogled-chromium is unsupported).

Status: **planned, not implemented.** Written for a follow-up dev session.
Decisions already made by the maintainer are marked **[decided]**.

---

## 1. What is actually broken

The issue is two independent defects that happen to look like one.

### D1 — FlicKey doesn't recognize most browsers *at all*

`AppRules.defaults` (`Sources/AppRules.swift:63`) hardcodes eight browsers and matches them by
**display name** against `NSRunningApplication.localizedName`:

```
Safari, Google Chrome, Microsoft Edge, Brave Browser, Firefox, Arc, Opera, Vivaldi
```

Anything else — Zen (`app.zen-browser.zen`), ungoogled-chromium (`Chromium` /
`org.chromium.Chromium`), LibreWolf, Floorp, Waterfox, Firefox Developer Edition/Nightly, Orion —
never matches, so `AppRouting.decide` returns `.leaveAsIs` and `TabMemory` is never engaged. Per-site
memory is not degraded for these browsers; it is entirely absent.

Worse, the obvious user workaround makes it *worse*: adding the browser via **Settings → Apps → Add**
creates a custom entry with `kind: .normal` and `autoByDefault: false` (`AppRules.swift:130`), i.e. a
**forced** language for the whole browser. There is currently no way for a user to mark an app as a
browser.

### D2 — Gecko browsers can't be read even once recognized

`BrowserURLReader.unsupported = ["Firefox"]` (`Sources/BrowserURLReader.swift:33`) short-circuits to
`.failed` → `.unreadable`, and that is honest: Firefox ships no AppleScript vocabulary for reading the
active tab's URL. Every Gecko fork inherits this. The URL has to come from somewhere else.

### Two latent bugs this work should sweep up

- `BrowserURLReader` builds `tell application "<localizedName>"`. Name-based Apple Event targeting is
  ambiguous (two apps named `Chromium`) and breaks if a bundle is renamed. Use
  `tell application id "<bundleID>"`.
- `focusedWindowTitle(ofAppNamed:)` (`BrowserURLReader.swift:127`) re-finds the app by scanning
  `runningApplications` for a matching `localizedName` on **every poll** (0.7 s), when `TabMemory`
  already holds the `NSRunningApplication` and its pid.

---

## 2. Decisions

| Question | **[decided]** |
|---|---|
| How to recognize a browser | **Auto-discover via LaunchServices** — ask macOS which installed apps handle `https://`. Zen, ungoogled-chromium and every future browser appear automatically. |
| Validation | **Install Firefox + Zen locally** (`brew install --cask firefox zen`) and write an AX spike script *before* app code. |
| Delivery | **One release** (0.5.4): recognition + Gecko URL reading ship together. |
| Gecko with `accessibility.force_disabled=1` | **Silent no-op + document it.** Fall back to `.unreadable` (keep the prior tab) — identical to today's behavior, so no regression. Note the requirement in `README.md` / `TESTING.md`. No new UI. |

---

## 3. Design

### 3.1 `BrowserTarget` — identify the browser by bundle ID + pid, not name

```swift
struct BrowserTarget: Equatable {
    let name: String       // localizedName, for display + diagnostics
    let bundleID: String   // identity: AppleScript targeting, catalog lookup, core reset
    let pid: pid_t         // AX reads
}
```

`TabMemory` stores this instead of `browserName` (`Sources/TabMemory.swift:31`). Recreate
`ConversationMemoryCore` when **bundleID** changes (not name, not pid — pid changes on relaunch but
the site memory namespace is shared and must survive that).

### 3.2 New: `Sources/BrowserCatalog.swift` — *which apps are browsers, and how do we read them*

```swift
enum TabReadStrategy: Equatable {
    case appleScript(tabPhrase: String)   // "active tab" (Chromium) | "current tab" (Safari)
    case accessibility                    // AXWebArea → AXURL (Gecko + anything unknown)
}

struct BrowserInfo: Equatable { let name: String; let bundleID: String; let strategy: TabReadStrategy }

enum BrowserCatalog {
    static func installed() -> [BrowserInfo]                 // cached
    static func info(forBundleID id: String) -> BrowserInfo?
    static func invalidate()
    static func strategy(forBundleAt url: URL) -> TabReadStrategy   // pure → unit-testable
}
```

**Discovery.** `NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)`
— public, non-deprecated, macOS 12+ (deployment target is 13.0, `project.yml:6`). Returns every
installed `https` handler.

**Naming — do NOT use the filename.** `AppRules` matchKeys and `AppWatcher` routing both key off
`NSRunningApplication.localizedName` (`CFBundleDisplayName`/`CFBundleName` + localized
`InfoPlist.strings`), while `AppFinder.displayName` uses the *filename*. These differ (`Zen
Browser.app` whose `CFBundleName` is `Zen`), and a mismatch silently breaks routing. Derive the name
from the bundle: running app's `localizedName` if the app is running, else
`CFBundleDisplayName` → `CFBundleName` → filename, in that order.

**Strategy classification** (pure, over a bundle path):

1. `Info.plist` declares `OSAScriptingDefinition` → read that `.sdef` from `Contents/Resources`
   (cap the read, e.g. first 256 KB, case-insensitive):
   - contains `active tab` → `.appleScript("active tab")`   *(Chrome, Edge, Brave, Vivaldi, Opera, Arc, ungoogled-chromium)*
   - contains `current tab` → `.appleScript("current tab")` *(Safari-shaped)*
2. bundleID `com.apple.Safari` → `.appleScript("current tab")` — hardcoded guard, Safari's terminology
   isn't in a conventional sdef.
3. Anything else, or any read failure → `.accessibility`.

This is a **capability probe, not an engine guess**, so a new Chromium fork works with no code change.
Critically it never sends a speculative Apple Event, so FlicKey does not trigger a
"FlicKey wants to control Zen" TCC prompt for a browser it will read via AX anyway.

**Caching is mandatory.** `AppRules.all` is recomputed on *every* app activation
(`AppWatcher.swift:54`) and once per running app inside `FocusWatcher.sync()`
(`FocusWatcher.swift:199`). An uncached LaunchServices scan + disk reads there would be a real
regression. Memoize `installed()`; invalidate on `NSWorkspace` `didLaunchApplicationNotification`,
on volume mount/unmount, on `.appRulesChanged`, and behind a TTL backstop (~60 s).

### 3.3 `AppRules` — browsers become a discovered section

- Delete the eight browser rows from `defaults`. Append discovered browsers using the **same pattern
  and the same position** as today — i.e. before custom apps, so a legacy custom entry can't shadow a
  browser row (`ConversationProviderRegistry.installedApps()` at `AppRules.swift:139` is the model:
  `.auto` default, honors `hiddenBuiltins`, skips `seen` keys).
- **matchKey stays `name.lowercased()`.** `"safari"`, `"google chrome"` etc. are unchanged, so every
  persisted override and hidden-builtin carries over with **zero migration**.
- **Migration case that does need code:** a user who worked around D1 by adding Zen/Chromium as a
  custom app has a forced-language `.normal` row. Mirror the existing conversation-provider guard
  (`AppRules.swift:124`): skip a custom entry whose bundleID is a discovered browser, so the browser
  row wins and per-site memory engages. Also make `addCustom` refuse (or re-route) a bundleID that is
  a known browser.
- **Route by bundle ID.** Add `AppRules.rule(for app: NSRunningApplication)` that matches bundleID
  first and falls back to normalized name; `AppWatcher.handle` calls it. Persistence stays name-keyed;
  only *routing* becomes robust to renamed/localized bundles. `rule(forNormalizedName:)` stays for
  `FocusWatcher`/tests.

### 3.4 `BrowserURLReader` — strategy-dispatched

- `state(for target: BrowserTarget) -> TabState`, dispatching on `BrowserCatalog.info(forBundleID:)`.
- Drop `unsupported`.
- AppleScript path: `tell application id "<bundleID>"`, focused-window scoping unchanged, but the
  window title comes from `target.pid` (no `runningApplications` scan).
- Keep `ReadResult` (`.value` / `.blank` / `.failed`) as the single seam. The
  missing-value-vs-error distinction documented at `BrowserURLReader.swift:21` is the most
  load-bearing invariant in this file — **the AX reader must map into the same three cases**, or a
  transient AX failure will be mistaken for a blank tab and clobber the remembered site.
- `isNewTabURL`: add the Gecko set — `about:newtab`, `about:home`, `about:blank` (present),
  `about:privatebrowsing`, and whatever Zen/`moz-extension://…` new-tab overrides the spike reveals.

### 3.5 New: `Sources/AccessibilityURLReader.swift`

```swift
enum AccessibilityURLReader {
    static func read(pid: pid_t) -> BrowserURLReader.ReadResult
}
```

1. `kAXFocusedWindowAttribute` on the app element. None → `.failed`.
2. **Fast path:** `AXDocument` / `AXURL` on the window itself.
   `scripts/safari-url-ax-probe.swift` already inspects exactly this — extend it rather than
   reinventing. One AX call if it works.
3. **Fallback:** bounded BFS from the window for `AXRole == "AXWebArea"`. Hard caps: depth ≤ 12,
   nodes ≤ 400, and `AXUIElementSetMessagingTimeout(app, 1.0)` (same guard `ChromiumAX.enable` uses,
   `ChromiumAX.swift:27`) so an unresponsive browser can't stall the poll.
4. **Cache the found element per pid**, or the 0.7 s poll re-walks the tree forever. Re-validate by
   reading `AXURL`; on `kAXErrorInvalidUIElement` drop the cache and re-walk. Clear on
   `leftBrowser()` and on focused-window change (`TitleChangeHint` already observes
   `kAXFocusedWindowChangedNotification`, `DetectionHints.swift:57`).
5. Read `AXURL` (a `CFURL`) → `absoluteString`. Walk succeeded but no/empty URL → `.blank`; walk
   failed → `.failed`.
6. **Multiple web areas** (Zen split view, PiP, sidebar): prefer the one containing the focused UI
   element, else the largest by `AXSize`, else the first. The spike decides.

Firefox activates its a11y engine when an AT queries the tree — no `AXManualAccessibility` equivalent
is expected. Confirm in the spike; if a nudge *is* needed, follow `ChromiumAX`'s toggle pattern in a
Gecko-specific helper rather than widening `ChromiumAX`.

Follow the house style: document the *why* in a header comment (see `ChromiumAX.swift` and
`BrowserURLReader.swift`) and record the spike's answers there.

---

## 4. Spike first — `scripts/gecko-url-ax-probe.swift`

Model on `scripts/safari-url-ax-probe.swift`. **No app code until these are answered:**

1. Does Firefox's focused window expose `AXDocument` or `AXURL` directly? (Decides whether the BFS is
   even needed.)
2. Where is the `AXWebArea` — role chain and depth from the window? What type is `AXURL`?
3. Does `AXURL` update immediately on tab switch, or lag? Compare against the 0.7 s poll + 80 ms hint
   (`TabMemory.swift:41,53`).
4. How many `AXWebArea`s exist with several tabs open — only the selected one, or all?
5. Zen split view: two live web areas — how do we pick the focused one?
6. What does `AXURL` report for `about:newtab`, `about:home`, `about:blank`, and a private window?
7. Multiple windows: is app-level `kAXFocusedWindowAttribute` correct, or does it need the
   window-title disambiguation the AppleScript path resorts to (`BrowserURLReader.swift:83`)?
8. Cost of a warm read (target < 20 ms; must be ≪ 700 ms).
9. Cold start: does it work right after Firefox launches, before any AT has touched it?
10. With `accessibility.force_disabled=1`: does it fail fast, or hang?

Also run the probe against **Chromium/ungoogled-chromium** to confirm the AppleScript path is what it
actually uses (it should be — its sdef has `active tab`).

---

## 5. Testing

### 5.1 Unit — headless, `scripts/test.sh browser`

Everything but the AX walk itself must stay behind a pure seam.

**New `Tests/BrowserCatalogTests.swift`**
- `strategy(forBundleAt:)` against synthesized fixture bundles in a temp dir:
  sdef with `active tab` → `.appleScript("active tab")`; `current tab` → `.appleScript("current tab")`;
  no `OSAScriptingDefinition` → `.accessibility`; sdef path present but file missing → `.accessibility`;
  garbage/binary sdef → `.accessibility`; no `Info.plist` → `.accessibility`.
- Name derivation prefers `CFBundleDisplayName` → `CFBundleName` → filename.
- `installed()` finds Safari on any dev Mac (`XCTSkip` if not, like the conversation-provider tests).
- `invalidate()` forces a re-scan.

**Extend `Tests/BrowserURLReaderTests.swift`**
- `isNewTabURL` over the Gecko set (per spike findings).
- `classify("about:reader?url=…")` → assert and document the chosen behavior.
- Assert the AX reader's outcomes funnel through the same `state(from:)` matrix — the `.blank` vs
  `.failed` distinction is the regression risk.

**Extend `Tests/AppRulesTests.swift`**
- Rewrite `testBrowsersDefaultToAuto` to iterate `AppRules.all.filter { $0.kind == .browser }` rather
  than naming Safari.
- Back-compat: seed `appInputOverrides["safari"]` directly into `UserDefaults` and assert the
  discovered Safari row honors it.
- Hide a discovered browser → gone; re-add → restored.
- A custom entry whose bundleID is a discovered browser does not shadow the browser row
  (mirrors `testCustomEntryDoesNotShadowConversationProvider`).
- `AppRoutingTests`: add a case asserting a browser-kind rule still routes `.browser` (logic is
  unchanged, this is a guard).

**`project.yml`:** add `Sources/BrowserCatalog.swift` to the `FlicKeyTests` `sources` list. Keep
`AccessibilityURLReader.swift` out unless it grows a pure helper worth covering.

### 5.2 UI — opt-in, live

Extend `UITests/BrowserIntegrationUITests.swift` with a Firefox variant reusing the existing
`-uiTestSeedSites` seeding, `XCTSkip`-guarded when Firefox isn't installed. Add a
`scripts/test.sh browser-ui-firefox` component. Keep it **out** of the default UI run, same
flakiness reasoning as the Safari one (`TESTING.md`).

### 5.3 Manual QA — this is the real gate

Add to `QA_TEST_PLAN.md` §C. Re-run **C1–C11 unchanged** against each engine, plus:

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| C12 | Gecko per-site memory | C1 + C2 in Firefox | Keyboard flips per site; **no** Automation prompt |
| C13 | Zen | C1 + C2 in Zen | Same as C12 |
| C14 | Zen split view | Two sites side by side; click between panes | Follows the focused pane, or a documented limitation |
| C15 | ungoogled-chromium | C1 + C2 in `Chromium.app` | Works; Automation prompt names "Chromium" |
| C16 | Private window | Known site in a Firefox private window | Memory applies (or documented: no memory in private) |
| C17 | Gecko new tab | ⌘T in Firefox/Zen | New-tab preference applies, not the prior site's layout |
| C18 | a11y disabled | `accessibility.force_disabled=1`, restart Firefox | No crash, no hang, no beachball; layout simply doesn't auto-switch |
| C19 | Discovery churn | Install/remove a browser while FlicKey runs | Settings → Browsers reflects it within a poll / on reopen |
| C20 | Legacy custom entry | Pre-upgrade user who added "Zen" as a custom app | After upgrade it appears under **Browsers** as Auto, not a forced language |
| C21 | Perf | Firefox with ~50 tabs, rapid ⌃Tab | No beachball; CPU flat; no AX-walk stall |
| C22 | Mixed browsers | Safari → Firefox → Chromium, each on a different site | Each read via its own strategy; no cross-talk |

Also re-run **C6, C7, C8, J3** (force/auto override precedence, handoff) against a Gecko browser, and
**E9, E10** for the now-dynamic Browsers section.

Update the `TESTING.md` manual checklist item 3 to name a Gecko browser and the a11y caveat.

---

## 6. Risks and open items

- **AXURL lag on tab switch.** If Gecko updates `AXURL` after the title change, the 80 ms
  `probeDelay` may fire too early. May need a strategy-specific delay or one retry.
- **Zen is a fast-moving fork.** Its AX shape may drift from Firefox's; test both, and prefer the
  generic BFS over any Zen-specific assumption.
- **Firefox a11y engine cost.** Mitigated by the existing design — `TabMemory` only polls while the
  browser is frontmost. If the spike shows a real cost, that's the lever to tighten.
- **Discovery noise.** Non-browser apps register as `https` handlers (some Electron apps, IDEs). If
  the Browsers section gets noisy, filter to bundles that look like browsers (have an sdef with tab
  vocabulary, or yield an `AXWebArea`) — but only add that filter if the noise is real.
- **Name-keyed persistence collides** for two same-named installs (`Chromium` in `/Applications` and
  `~/Applications`). Out of scope; routing-by-bundleID (§3.3) reduces the blast radius. Note it.
- **`ChromiumAX` overlap.** Chromium browsers read via AppleScript, so the AX path shouldn't need
  `AXManualAccessibility`. Don't wire them together without a reason.

---

## 7. Suggested commit sequence

1. `scripts/gecko-url-ax-probe.swift` + findings recorded — no app change.
2. `BrowserCatalog` + pure unit tests.
3. `BrowserTarget` plumbed through `TabMemory` / `BrowserURLReader`; AppleScript targeted by bundle
   id; pid-based window title. **Behavior-neutral** — existing tests must stay green.
4. `AppRules` discovery + routing-by-bundleID + tests + legacy-custom-entry handling.
5. `AccessibilityURLReader` + new-tab prefixes + tests.
6. Docs: `README.md`, `TESTING.md`, `QA_TEST_PLAN.md`.
7. Version bump to 0.5.4, full manual QA pass, reply on issue #1.

Rough size: ~1–2 days including the spike and the manual QA pass.
