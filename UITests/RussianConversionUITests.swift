import Carbon
import CoreGraphics
import XCTest

// Live conversion with the native Russian layout in TextEdit. Keep the guest's
// usual ABC + Hebrew fixtures intact for the rest of the UI suite.
final class RussianConversionUITests: XCTestCase {
    private let abcID = "com.apple.keylayout.ABC"
    private let russianID = "com.apple.keylayout.Russian"
    private var previouslyEnabled: Set<String>?
    private var previouslySelected: String?
    private var flickey: XCUIApplication!
    private var textEdit: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let sources = try keyboardLayouts()
        let abc = try XCTUnwrap(sources.first { sourceID($0) == abcID })
        let russian = try XCTUnwrap(sources.first { sourceID($0) == russianID })
        previouslyEnabled = Set(sources.filter(isEnabled).map(sourceID))
        previouslySelected = currentInputSourceID()

        XCTAssertEqual(TISEnableInputSource(abc), noErr)
        XCTAssertEqual(TISEnableInputSource(russian), noErr)
        XCTAssertEqual(TISSelectInputSource(abc), noErr)
        for source in sources where sourceID(source) != abcID && sourceID(source) != russianID && isEnabled(source) {
            XCTAssertEqual(TISDisableInputSource(source), noErr)
        }
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.enabledIDs() == Set([self.abcID, self.russianID])
                && currentInputSourceID() == self.abcID
        }, "The VM must have only ABC and Russian enabled for this two-layout test")

        flickey = XCUIApplication()
        flickey.launchArguments = ["-uiTestReset"]
        flickey.launch()

        textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                                    "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        textEdit.launch()
    }

    override func tearDownWithError() throws {
        textEdit?.terminate()
        flickey?.terminate()
        forceLatinInputSource()
        if let previouslyEnabled, let sources = try? keyboardLayouts() {
            for source in sources {
                let status = previouslyEnabled.contains(sourceID(source))
                    ? TISEnableInputSource(source) : TISDisableInputSource(source)
                XCTAssertEqual(status, noErr)
            }
            if let previouslySelected { selectInputSource(id: previouslySelected) }
        }
    }

    func testEnglishMistakeConvertsToRussianAndBack() throws {
        let field = try freshDocument()
        step("Type ghbdtn in TextEdit under ABC")
        field.typeText("ghbdtn")
        XCTAssertEqual(field.value as? String, "ghbdtn")

        step("Double-Shift converts to привет and selects Russian")
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "привет" }))
        XCTAssertTrue(waitForSource(russianID, 5))

        step("Double-Shift again restores ghbdtn and ABC")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "ghbdtn" }))
        XCTAssertTrue(waitForSource(abcID, 5))
    }

    func testRussianPhysicalTypingConvertsToEnglish() throws {
        let field = try freshDocument()
        step("Select Russian and physically type the keys for hello")
        selectInputSource(id: russianID)
        XCTAssertTrue(waitForSource(russianID, 5))
        for key in [CGKeyCode(4), 14, 37, 37, 31] {
            postPhysicalShortcut(keyCode: key, flags: [])
        }
        XCTAssertTrue(waitUntil(timeout: 5) { (field.value as? String) == "руддщ" },
                      "Expected Russian wrong-layout text, got \(field.value ?? "nil")")

        step("Double-Shift converts руддщ to hello and selects ABC")
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "hello" }))
        XCTAssertTrue(waitForSource(abcID, 5))
    }

    private func freshDocument() throws -> XCUIElement {
        var field = textEdit.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            textEdit.typeKey("n", modifierFlags: .command)
            field = textEdit.textViews.firstMatch
            _ = try XCTUnwrap(field.waitForExistence(timeout: 5) ? field : nil)
        }
        field.click()
        textEdit.typeKey("a", modifierFlags: .command)
        textEdit.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { (field.value as? String) == "" })
        return field
    }

    private func keyboardLayouts() throws -> [TISInputSource] {
        let sources = try XCTUnwrap(TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource])
        return sources.filter { sourceID($0).hasPrefix("com.apple.keylayout.") }
    }

    private func enabledIDs() -> Set<String> {
        guard let sources = try? keyboardLayouts() else { return [] }
        return Set(sources.filter(isEnabled).map(sourceID))
    }

    private func sourceID(_ source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func isEnabled(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
