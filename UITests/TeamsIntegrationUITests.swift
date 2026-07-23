import XCTest
import AppKit
import ApplicationServices

// LIVE Teams integration tests (QA D2/D3/A8): drive the real Microsoft Teams
// app and assert the per-conversation pipeline end to end — FlicKey notices
// the open chat, remembers the layout the "user" picks in it, and re-applies
// it when returning.
//
// Teams is an Electron/WebView app, which makes it hostile to automation in
// two specific ways this file works around:
//   • it exposes only a skeleton AX tree until an assistive client asks for
//     more — setUp flips the AXManualAccessibility attribute to force the
//     full tree on;
//   • clicking a bare static text doesn't dispatch to the web layer — chat
//     rows are clicked through their interactive role (button/cell/link)
//     at their coordinates, with a ⌘E-search fallback for opening chats.
//
// Like BrowserIntegrationUITests this is the flaky frontier and is EXCLUDED
// from the default UI run — run it via `scripts/test.sh teams-ui`. It skips
// cleanly when Teams isn't installed, isn't logged in, or never shows a chat.
//
// The real title parser (TeamsConversationProvider) is compiled into this test
// bundle, so the "is this an open chat" check is exactly the app's own logic.
final class TeamsIntegrationUITests: XCTestCase {

    private static let teamsBundleID = "com.microsoft.teams2"

    private var flickey: XCUIApplication!
    private var teams: XCUIApplication!
    private var latin = ""
    private var other = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.teamsBundleID) != nil else {
            throw XCTSkip("Microsoft Teams (new) is not installed")
        }
        guard let pair = twoEnabledLayouts() else {
            throw XCTSkip("Needs two enabled keyboard layouts (e.g. ABC + Hebrew).")
        }
        (latin, other) = pair
        forceLatinInputSource()

        step("Launch FlicKey (isolated store) + Microsoft Teams")
        flickey = XCUIApplication()
        flickey.launchArguments = ["-uiTestReset"]
        flickey.launch()

        teams = XCUIApplication(bundleIdentifier: Self.teamsBundleID)
        // Chromium honors this flag by building the full AX tree from launch
        // (harmless if the native shell doesn't forward it).
        teams.launchArguments = ["--force-renderer-accessibility"]
        teams.launch()
        enableChromiumAccessibility()
    }

    override func tearDownWithError() throws {
        forceLatinInputSource()
        teams.terminate()
        flickey.terminate()
    }

    // QA D2 (live): learn a layout in the open chat, leave, return → it's
    // re-applied. We never seed anything: the only way the keyboard can end up
    // on the non-Latin layout after re-activating Teams is FlicKey recalling
    // what it learned for that conversation.
    func testPerConversationLearnAndRecallLive() throws {
        let key = try waitForOpenChat()
        step("Live chat detected: “\(key)”")

        // Make sure FlicKey saw the Teams activation (not just the launch).
        activateFinder(for: 1.0)
        teams.activate()
        pause(1.5)

        step("LEARN: select \(other) while in the chat")
        selectInputSource(id: other)
        pause(1.0)   // let the TIS notification land

        step("Leave Teams (Finder), force the keyboard back to Latin")
        activateFinder(for: 1.0)
        forceLatinInputSource()
        pause(0.5)

        step("RECALL: re-activate Teams → keyboard should flip back to \(other)")
        teams.activate()
        XCTAssertTrue(waitForSource(other, 20),
                      "returning to the chat should restore \(other); current=\(currentInputSourceID())")
        step("Result: keyboard is now \(currentInputSourceID())")
    }

    // QA A8 (live, and visibly so): the wrong-layout FIX works inside Teams.
    // Types gibberish into the compose box, double-taps Shift, and FlicKey
    // converts it in place — proven by the layout switching — then SENDS it,
    // so the converted message lands in the chat as a visible artifact.
    func testConversionInsideTeamsComposeAndSend() throws {
        _ = try waitForOpenChat()
        focusCompose()

        step("Type wrong-layout gibberish 'akuo' into the compose box")
        forceLatinInputSource()
        teams.typeText("akuo")
        pause(0.5)

        step("Double-tap Shift — FlicKey should convert it in place")
        doubleTapShift()
        // The conversion's observable side effect: the keyboard switches to the
        // converted language.
        XCTAssertTrue(waitForSource(other, 15),
                      "the fix should fire and switch the layout to \(other); current=\(currentInputSourceID())")

        step("Send the converted message (visible proof in the chat)")
        pause(1.0)   // let the retype finish
        teams.typeKey(.return, modifierFlags: [])
        pause(1.0)
    }

    // QA D3, the full per-person story, visibly: teach two chats two different
    // languages, then hop between them and watch the keyboard follow — and
    // post a message into each chat saying what FlicKey just did.
    //
    private static let chatA = ProcessInfo.processInfo.environment["TEAMS_CHAT_A"] ?? "Dana Bloom"
    private static let chatB = ProcessInfo.processInfo.environment["TEAMS_CHAT_B"] ?? "noa nir"

    // The two test contacts are configurable so the suite runs against any Teams
    // tenant: set TEST_RUNNER_TEAMS_CHAT_A / TEST_RUNNER_TEAMS_CHAT_B when invoking
    // xcodebuild (the TEST_RUNNER_ prefix forwards them into this process). The
    // defaults are fictional placeholders (Latin names match reliably in Teams'
    // AX tree; chat B also exercises tenant-tag
    // stripping live). Skips if either chat can't be opened.
    func testTwoChatsTwoLanguagesFollowTheUser() throws {
        _ = try waitForOpenChat()   // make sure the Chat section is up

        step("Open '\(Self.chatA)' and pick \(other) — FlicKey learns it for this chat")
        try openChat(named: Self.chatA)
        pause(1.2)                          // let FlicKey enter; clear the grace window
        selectInputSource(id: other)
        pause(1.0)                          // let the learn land

        step("Open '\(Self.chatB)' and pick \(latin) — learned for THIS chat")
        try openChat(named: Self.chatB)
        pause(1.2)
        selectInputSource(id: latin)
        pause(1.0)

        step("Back to '\(Self.chatA)' → keyboard should flip to \(other) on its own")
        try openChat(named: Self.chatA)
        XCTAssertTrue(waitForSource(other, 15),
                      "returning to \(Self.chatA) should restore \(other); current=\(currentInputSourceID())")
        sendMessage("FlicKey ✓ עברית שוחזרה אוטומטית לצ'אט הזה")

        step("Back to '\(Self.chatB)' → keyboard should flip to \(latin) on its own")
        try openChat(named: Self.chatB)
        XCTAssertTrue(waitForSource(latin, 15),
                      "returning to \(Self.chatB) should restore \(latin); current=\(currentInputSourceID())")
        sendMessage("FlicKey ✓ auto-switched back to English for this chat")
    }

    // MARK: - Chromium accessibility

    // New Teams on macOS is WebView2/Chromium — NOT Electron — and Chromium
    // only builds its full AX tree when it believes a screen reader is
    // present: it watches for VoiceOver's AXEnhancedUserInterface attribute on
    // the application/window elements. (Electron's AXManualAccessibility is
    // ignored by WebView2; set anyway for Electron-era clients.) The tree
    // populates LAZILY after the flag flips — the first walk can come back
    // empty — so re-assert it once windows exist and give it time.
    private func enableChromiumAccessibility() {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == Self.teamsBundleID }) else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // Chromium watches the windows too; set the flag on each one.
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                AXUIElementSetAttributeValue(window, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
        pause(2.0)   // lazy tree build
        step("  · Teams AX tree after enabling: \(teams.buttons.count) buttons, \(teams.staticTexts.count) texts")
    }

    // MARK: - navigation helpers

    // The key the app's parser derives from Teams' current window title.
    private var currentChatKey: String? {
        TeamsConversationProvider.conversationKey(fromWindowTitle: teams.windows.firstMatch.title)
    }

    // Bring Teams to its Chat section and wait until the window title parses as
    // an open conversation (Teams usually opens the most recent chat). Skips if
    // that never happens (logged out, first-run screens, …).
    private func waitForOpenChat() throws -> String {
        let deadline = Date().addingTimeInterval(75)
        var lastTitle = ""
        var axRetriggered = false
        while Date() < deadline {
            teams.activate()
            pause(2.0)
            guard teams.windows.firstMatch.exists else { continue }
            if !axRetriggered {
                // The window may not have existed when setUp set the flag —
                // re-assert it now that one does (Chromium gates on the window).
                enableChromiumAccessibility()
                axRetriggered = true
            }
            teams.typeKey("2", modifierFlags: .command)   // ⌘2 = Chat section
            pause(2.5)
            lastTitle = teams.windows.firstMatch.title
            if let key = TeamsConversationProvider.conversationKey(fromWindowTitle: lastTitle) {
                return key
            }
        }
        throw XCTSkip("Teams never showed an open chat (logged out?). Last title: “\(lastTitle)”")
    }

    // The clickable chat-list row for a contact. Rows are interactive elements
    // (button/cell/link) whose compound label CONTAINS the name ("Dana Bloom
    // You: … 09/06"); a bare static text is the last resort.
    private func chatListEntry(named name: String) -> XCUIElement? {
        let labelled = NSPredicate(format: "label CONTAINS %@", name)
        let candidates = [
            teams.buttons.matching(labelled).firstMatch,
            teams.cells.matching(labelled).firstMatch,
            teams.links.matching(labelled).firstMatch,
            teams.staticTexts[name].firstMatch,
        ]
        return candidates.first { $0.exists && $0.isHittable }
    }

    // Open a chat by contact name: click its list row (by coordinate — actor
    // clicks on Electron elements often don't dispatch), retry with a plain
    // click, then fall back to ⌘E search. Confirms via the window title using
    // the app's own parser.
    private func openChat(named name: String) throws {
        if currentChatKey == name { return }   // already open

        func opened() -> Bool { waitUntil(timeout: 8) { self.currentChatKey == name } }

        if let entry = chatListEntry(named: name) {
            entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            if opened() { return }
            step("  · coordinate click didn't open '\(name)' — retrying a plain click")
            entry.click()
            if opened() { return }
        }

        step("  · falling back to ⌘E search for '\(name)'")
        teams.typeKey("e", modifierFlags: .command)
        pause(1.0)
        teams.typeText(name)
        pause(1.5)
        teams.typeKey(.downArrow, modifierFlags: [])
        teams.typeKey(.return, modifierFlags: [])
        guard opened() else {
            throw XCTSkip("couldn't open chat '\(name)' (current title: “\(teams.windows.firstMatch.title)”)")
        }
    }

    // MARK: - compose helpers

    // The message compose box: a text area/field, found by role or by its
    // "Type a message" label.
    private func composeBox() -> XCUIElement? {
        let typeAMessage = NSPredicate(format: "label CONTAINS[c] %@ OR placeholderValue CONTAINS[c] %@",
                                       "type a message", "type a message")
        let candidates = [
            teams.textViews.firstMatch,
            teams.textFields.firstMatch,
            teams.textViews.matching(typeAMessage).firstMatch,
            teams.otherElements.matching(typeAMessage).firstMatch,
        ]
        return candidates.first { $0.exists && $0.isHittable }
    }

    // Put focus in the compose box. When it isn't findable in the AX tree,
    // type blind — Teams places focus in compose after opening a chat.
    private func focusCompose() {
        if let compose = composeBox() {
            compose.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        } else {
            step("  · compose box not in the AX tree — typing blind (focus lands there by default)")
        }
        pause(0.5)
    }

    // Type + send a message in the open chat — the visible artifact of the run.
    private func sendMessage(_ text: String) {
        focusCompose()
        teams.typeText(text)
        teams.typeKey(.return, modifierFlags: [])
        pause(0.8)
    }

    // MARK: - misc

    private func activateFinder(for seconds: TimeInterval) {
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        pause(seconds)
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
