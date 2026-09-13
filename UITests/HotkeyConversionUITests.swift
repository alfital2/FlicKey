import XCTest

// The product's #1 feature, end to end: type wrong-layout gibberish into a real
// text field (TextEdit), double-tap Shift, and assert the text physically
// becomes the intended word AND the keyboard switches to its language.
//
// This exercises the full instant-conversion path live: the typing buffer
// captures the keystrokes, the double-tap detector fires on the synthetic
// Shift taps, and the fix deletes + retypes in place. Runs in the default UI
// suite (TextEdit is deterministic); needs FlicKey's Accessibility grant,
// and skips unless ABC + Hebrew-PC are the two enabled layouts (the expected
// output "שלום" is layout-specific).
final class HotkeyConversionUITests: XCTestCase {

    private var flickey: XCUIApplication!
    private var textEdit: XCUIApplication!
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

        textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
    }

    override func tearDownWithError() throws {
        forceLatinInputSource()
        textEdit.terminate()
        flickey.terminate()
    }

    // QA A1 (the core promise): gibberish → ⇧⇧ → the intended word, keyboard
    // switched to its language.
    func testDoubleShiftFixesWrongLayoutTextInPlace() throws {
        let textView = try freshDocument()

        step("Type 'akuo' (שלום typed on the wrong layout) into TextEdit")
        textView.typeText("akuo")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        step("Double-tap Shift — expect the text to become שלום and the keyboard to flip")
        XCTAssertTrue(triggerFix(until: { (textView.value as? String) == "שלום" }),
                      "the text should be fixed in place; field=\"\(textView.value as? String ?? "")\"")
        XCTAssertTrue(waitForSource(hebrew, 5),
                      "the keyboard should switch to Hebrew; current=\(currentInputSourceID())")
    }

    // QA A6-adjacent: a second ⇧⇧ converts straight back (the buffer adopts the
    // converted text, so an immediate re-trigger cycles).
    func testSecondDoubleShiftTogglesBack() throws {
        let textView = try freshDocument()

        textView.typeText("akuo")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        step("⇧⇧ → שלום")
        XCTAssertTrue(triggerFix(until: { (textView.value as? String) == "שלום" }),
                      "first fix should land; field=\"\(textView.value as? String ?? "")\"")

        step("⇧⇧ again → back to akuo")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))   // let the buffer adopt
        XCTAssertTrue(triggerFix(until: { (textView.value as? String)?.lowercased() == "akuo" }),
                      "second fix should toggle back; field=\"\(textView.value as? String ?? "")\"")
    }

    func testCustomShortcutReplacesOldTriggerAndPersists() throws {
        step("Record ⌃⌥9 through Settings")
        flickey.terminate()
        flickey.launchArguments = ["-uiTestReset", "-uiTestOpenSettings"]
        flickey.launch()
        flickey.tab("Shortcut").click()
        let current = flickey.staticTexts["currentShortcut"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        flickey.buttons["recordShortcut"].click()
        flickey.typeKey("9", modifierFlags: [.control, .option])
        XCTAssertTrue(waitUntil(timeout: 4) { (current.value as? String) == "⌃⌥9" })
        flickey.typeKey("w", modifierFlags: .command)

        let textView = try freshDocument()
        textView.typeText("akuo")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        step("The old double-Shift trigger must no longer convert")
        doubleTapShift()
        XCTAssertFalse(waitUntil(timeout: 1.5) { (textView.value as? String) == "שלום" })

        step("The recorded chord performs the conversion")
        textEdit.typeKey("9", modifierFlags: [.control, .option])
        XCTAssertTrue(waitUntil(timeout: 8) { (textView.value as? String) == "שלום" })

        step("Relaunch and verify the custom trigger is retained")
        flickey.terminate()
        flickey.launchArguments = ["-uiTestPreserveState", "-uiTestOpenSettings"]
        flickey.launch()
        flickey.tab("Shortcut").click()
        XCTAssertEqual(flickey.staticTexts["currentShortcut"].value as? String, "⌃⌥9")
    }

    // MARK: - helpers

    // A focused, EMPTY TextEdit document. TextEdit restores previous-session
    // windows with whatever was in them (a live run surfaced the user's Hebrew
    // scratch text), so clear the target document before typing.
    private func freshDocument() throws -> XCUIElement {
        var textView = textEdit.textViews.firstMatch
        if !textView.waitForExistence(timeout: 5) {
            textEdit.typeKey("n", modifierFlags: .command)
            textView = textEdit.textViews.firstMatch
            guard textView.waitForExistence(timeout: 5) else {
                throw XCTSkip("TextEdit never showed a document text view")
            }
        }
        textView.click()
        textEdit.typeKey("a", modifierFlags: .command)   // select any restored content…
        textEdit.typeKey(.delete, modifierFlags: [])     // …and clear it
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return textView
    }

}
