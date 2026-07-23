import XCTest
import CoreGraphics

// End-to-end regression test for the Spotlight off-by-one fix: type wrong-layout
// gibberish into Spotlight's SEARCH field, double-tap Shift, and assert the query
// becomes the intended word with NO leftover Latin letter. Spotlight is the one
// field that actually reproduced the bug — its autocomplete suggestion is
// invisible to Accessibility and ate the first Backspace — so this guards the
// search-field replace path end to end.
//
// Driving/reading Spotlight from XCUITest is inherently finicky (it's a system
// overlay), so the test SKIPS gracefully when it can't see the field. It lives in
// the on-demand UI suite (scripts/run-ui-tests.sh), not the default CI action,
// and needs FlicKey's Accessibility grant + ABC/Hebrew-PC as the two layouts.
final class SpotlightConversionUITests: XCTestCase {

    private var flickey: XCUIApplication!
    private let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
    private let abc = "com.apple.keylayout.ABC"
    private let hebrew = "com.apple.keylayout.Hebrew-PC"

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let pair = twoEnabledLayouts(), pair.latin == abc, pair.other == hebrew else {
            throw XCTSkip("Needs ABC + Hebrew-PC as the two enabled keyboard layouts")
        }
        forceLatinInputSource()
        flickey = XCUIApplication()
        flickey.launchArguments = ["-uiTestReset"]   // default trigger: ⇧⇧
        flickey.launch()
    }

    override func tearDownWithError() throws {
        closeSpotlight()
        forceLatinInputSource()
        flickey.terminate()
    }

    // "asdasd" → ⇧⇧ → "שדגשדג", with no surviving Latin letter. The old
    // off-by-one left a leading "a" (and piled up on repeats); a correct
    // conversion is all-Hebrew.
    func testSpotlightSearchConvertsWithoutLeftoverLetter() throws {
        openSpotlight()
        guard fieldValue() != nil else {
            throw XCTSkip("Can't read Spotlight's search field via XCUITest on this machine")
        }

        step("Type 'asdasd' into Spotlight")
        clearSpotlight()
        type("asdasd")
        XCTAssertTrue(waitUntil(timeout: 3) { (fieldValue() ?? "").hasPrefix("asdasd") },
                      "Spotlight should hold the typed query; value=\"\(fieldValue() ?? "")\"")

        step("Double-tap Shift — expect 'שדגשדג' with no leftover Latin")
        let fixed = triggerFix { self.fieldValue() == "שדגשדג" }
        let result = fieldValue() ?? ""
        XCTAssertTrue(fixed, "Spotlight query should become שדגשדג; got \"\(result)\"")
        XCTAssertFalse(result.contains { $0.isASCII && $0.isLetter },
                       "no Latin letter should survive the conversion; got \"\(result)\"")
    }

    // MARK: - helpers

    private func openSpotlight() {
        postKey(49, flags: .maskCommand)                       // ⌘Space
        _ = spotlight.searchFields.firstMatch.waitForExistence(timeout: 3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
    private func closeSpotlight() { postKey(53, flags: []) }   // Esc

    private func clearSpotlight() {
        postKey(0, flags: .maskCommand)                        // ⌘A
        postKey(51, flags: [])                                 // delete
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


    // Type as Unicode CGEvents — they land in Spotlight AND are seen by FlicKey's
    // global typing-buffer monitor (so the conversion fires).
    private func type(_ s: String) {
        for ch in s {
            var units = Array(String(ch).utf16)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                up.post(tap: .cghidEventTap)
            }
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
}
