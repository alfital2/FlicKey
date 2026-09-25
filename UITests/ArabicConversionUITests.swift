import Carbon
import CoreGraphics
import XCTest

// Live Arabic PC conversion in TextEdit. Restore the guest's enabled layouts
// after each case so the Hebrew and Russian UI fixtures remain independent.
final class ArabicConversionUITests: XCTestCase {
    private let abcID = "com.apple.keylayout.ABC"
    private let arabicID = "com.apple.keylayout.ArabicPC"
    private var previouslyEnabled: Set<String>?
    private var previouslySelected: String?
    private var flickey: XCUIApplication!
    private var textEdit: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let sources = try keyboardLayouts()
        let abc = try XCTUnwrap(sources.first { sourceID($0) == abcID })
        let arabic = try XCTUnwrap(sources.first { sourceID($0) == arabicID })
        previouslyEnabled = Set(sources.filter(isEnabled).map(sourceID))
        previouslySelected = currentInputSourceID()

        XCTAssertEqual(TISEnableInputSource(abc), noErr)
        XCTAssertEqual(TISEnableInputSource(arabic), noErr)
        XCTAssertEqual(TISSelectInputSource(abc), noErr)
        for source in sources where sourceID(source) != abcID && sourceID(source) != arabicID && isEnabled(source) {
            XCTAssertEqual(TISDisableInputSource(source), noErr)
        }
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.enabledIDs() == Set([self.abcID, self.arabicID])
                && currentInputSourceID() == self.abcID
        }, "The VM must have only ABC and Arabic PC enabled")

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

    func testEnglishMistakeConvertsToArabicAndBack() throws {
        let field = try freshDocument()
        step("Type sghl under ABC")
        field.typeText("sghl")
        XCTAssertEqual(field.value as? String, "sghl")

        step("Double-Shift converts to سلام and selects Arabic PC")
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "سلام" }),
                      "ABC → Arabic result: \(field.value ?? "nil")")
        XCTAssertTrue(waitForSource(arabicID, 5))

        step("Double-Shift restores sghl and ABC")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "sghl" }),
                      "Arabic → ABC result: \(field.value ?? "nil")")
        XCTAssertTrue(waitForSource(abcID, 5))
    }

    func testArabicLigatureBKeyConvertsToBad() throws {
        let field = try freshDocument()
        selectInputSource(id: arabicID)
        XCTAssertTrue(waitForSource(arabicID, 5))
        step("Physically type b-a-d under Arabic PC; b emits لا")
        for key in [CGKeyCode(11), 0, 2] { postPhysicalShortcut(keyCode: key, flags: []) }
        XCTAssertTrue(waitUntil(timeout: 5) { (field.value as? String) == "لاشي" },
                      "Arabic b-a-d result: \(field.value ?? "nil")")

        step("Double-Shift converts لاشي to bad and selects ABC")
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "bad" }),
                      "Arabic ligature → ABC result: \(field.value ?? "nil")")
        XCTAssertTrue(waitForSource(abcID, 5))
    }

    func testSeparateArabicLamAlefKeysConvertToGH() throws {
        let field = try freshDocument()
        selectInputSource(id: arabicID)
        XCTAssertTrue(waitForSource(arabicID, 5))
        step("Physically type g-h under Arabic PC; the text is also لا")
        for key in [CGKeyCode(5), 4] { postPhysicalShortcut(keyCode: key, flags: []) }
        XCTAssertTrue(waitUntil(timeout: 5) { (field.value as? String) == "لا" },
                      "Arabic g-h result: \(field.value ?? "nil")")

        step("Double-Shift converts the separate keys to gh, not b")
        XCTAssertTrue(triggerFix(until: { (field.value as? String) == "gh" }),
                      "Arabic lam-alef → ABC result: \(field.value ?? "nil")")
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
