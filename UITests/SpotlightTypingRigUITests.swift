import XCTest
import CoreGraphics

// The FOUNDATION test for the Spotlight-driven UI suite: it proves the *rig*
// works before any test built on it can be trusted.
//
// Three stages, each asserted: type "hello" in a Latin layout, clear the field,
// then switch the system to Hebrew-PC and type the SAME physical keys "hello
// you" — which the layout turns into "יקךךם טםו". Nothing about FlicKey's
// behavior is asserted here; a failure means the harness itself is broken
// (can't drive Spotlight, can't switch layouts, or can't read back RTL text),
// which is exactly what you want to rule out first when a real test fails.
//
// Why physical keycodes and a real layout switch, rather than injecting the
// Hebrew as Unicode: injecting Unicode would prove only that Spotlight accepts
// RTL characters. Posting keycode 4 and getting "י" proves the whole layout
// pipeline is live — the same path a user's fingers take, and the same events
// FlicKey's typing-buffer monitor sees.
//
// Like the rest of the suite this drives the real screen, lives in the on-demand
// scheme (scripts/run-ui-tests.sh), and SKIPS gracefully when the machine lacks
// ABC + Hebrew-PC or when Spotlight's field can't be read via Accessibility.
final class SpotlightTypingRigUITests: XCTestCase {

    private var flickey: XCUIApplication!
    private let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
    private let abc = "com.apple.keylayout.ABC"
    private let hebrew = "com.apple.keylayout.Hebrew-PC"

    // "hello you" on Hebrew-PC. Written as the physical keys plus the text they
    // must produce, so the expectation and the input can't drift apart.
    private let latinKeys = "hello you"
    private let hebrewText = "יקךךם טםו"

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let pair = twoEnabledLayouts(), pair.latin == abc, pair.other == hebrew else {
            throw XCTSkip("Needs ABC + Hebrew-PC as the two enabled keyboard layouts")
        }
        forceLatinInputSource()
        flickey = XCUIApplication()
        flickey.launchArguments = ["-uiTestReset"]
        flickey.launch()
    }

    override func tearDownWithError() throws {
        closeSpotlight()
        forceLatinInputSource()
        flickey.terminate()
    }

    func testSpotlightAcceptsLatinThenClearsThenAcceptsHebrew() throws {
        openSpotlight()
        guard fieldValue() != nil else {
            throw XCTSkip("Can't read Spotlight's search field via XCUITest on this machine")
        }

        // Stage 1 — Latin in, Latin out.
        step("Type 'hello' into Spotlight (ABC)")
        clearSpotlight()
        typeKeys("hello")
        XCTAssertTrue(waitUntil(timeout: 3) { self.fieldValue() == "hello" },
                      "Spotlight should hold 'hello'; got \"\(fieldValue() ?? "<unreadable>")\"")

        // Stage 2 — the field can actually be emptied. Worth its own assertion:
        // a stale query silently prefixing the next stage is the single most
        // likely way a Spotlight test lies to you.
        step("Clear the field — expect it empty")
        clearSpotlight()
        XCTAssertTrue(waitUntil(timeout: 3) { self.isEmptyQuery(self.fieldValue()) },
                      "Spotlight should be empty after ⌘A+Delete; got \"\(fieldValue() ?? "<unreadable>")\"")

        // Stage 3 — same physical keys, different layout, Hebrew out.
        step("Switch to Hebrew-PC and type the keys '\(latinKeys)' — expect '\(hebrewText)'")
        selectInputSource(id: hebrew)
        XCTAssertTrue(waitForSource(hebrew, 3), "system should switch to Hebrew-PC before typing")
        typeKeys(latinKeys)
        XCTAssertTrue(waitUntil(timeout: 3) { self.fieldValue() == self.hebrewText },
                      "Hebrew-PC should turn '\(latinKeys)' into '\(hebrewText)'; got \"\(fieldValue() ?? "<unreadable>")\"")

        // Not an assertion — a breadcrumb. FlicKey is running and auto-switching
        // is exactly its job, so if it flips the layout mid-typing the stage-3
        // failure above would otherwise look like a broken rig. Say which it was.
        if currentInputSourceID() != hebrew {
            step("  · note: layout drifted to \(currentInputSourceID()) during typing (FlicKey auto-switch?)")
        }
    }

    // MARK: - Spotlight driving
    //
    // These mirror the private helpers in SpotlightConversionUITests. Once a
    // third Spotlight test appears they should be extracted into a shared
    // driver — deliberately left duplicated for now rather than refactoring a
    // passing test as a side effect of adding this one.

    private func openSpotlight() {
        postKey(49, flags: .maskCommand)                       // ⌘Space
        _ = spotlight.searchFields.firstMatch.waitForExistence(timeout: 3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func closeSpotlight() { postKey(53, flags: []) }   // Esc

    private func clearSpotlight() {
        postKey(0, flags: .maskCommand)                        // ⌘A
        postKey(51, flags: [])                                 // Delete
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    // The Spotlight query field's current text, via whichever role it exposes,
    // or nil if it can't be read.
    private func fieldValue() -> String? {
        for query in [spotlight.searchFields, spotlight.textFields] {
            let field = query.firstMatch
            if field.exists, let value = field.value as? String { return value }
        }
        return nil
    }

    // An empty query — some machines report the placeholder rather than "".
    private func isEmptyQuery(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Spotlight Search"
    }

    // MARK: - Typing by physical key

    // Post each character's PHYSICAL key, letting the active input source decide
    // which character appears. This is the difference that gives the test its
    // value: with Hebrew-PC selected, "hello" arrives as "יקךךם".
    private func typeKeys(_ keys: String) {
        for ch in keys {
            guard let code = Self.keyCode[ch] else {
                XCTFail("no key code mapped for '\(ch)' — extend SpotlightTypingRigUITests.keyCode")
                return
            }
            postKey(code, flags: [])
            usleep(35_000)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    // ANSI virtual key codes, keyed by the character they produce on a US layout.
    private static let keyCode: [Character: CGKeyCode] = [
        "a": 0,  "b": 11, "c": 8,  "d": 2,  "e": 14, "f": 3,  "g": 5,
        "h": 4,  "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,  "t": 17, "u": 32,
        "v": 9,  "w": 13, "x": 7,  "y": 16, "z": 6,  " ": 49,
    ]
}
