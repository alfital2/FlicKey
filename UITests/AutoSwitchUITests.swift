import XCTest

// The opt-in automatic correction path, including its explicit user escape
// hatch and learned exception. This is intentionally one end-to-end story:
// splitting it would repeat expensive dictionary/monitor startup three times.
final class AutoSwitchUITests: XCTestCase {
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
        flickey.launchArguments = ["-uiTestReset", "-uiTestEnableAutoSwitch",
                                   "-diagRecordEnabled", "YES"]
        flickey.launch()
        textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        // Keep the fixture's keystrokes intact. TextEdit otherwise sometimes
        // rewrites the leading "a" to "A" as a sentence-capitalization service,
        // turning the first token into a plausible proper noun before FlicKey
        // classifies it. Text-service mutation is covered separately by the
        // on-screen-span and conversion tests; this story is about auto-switch.
        textEdit.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                                    "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        textEdit.launch()
    }

    override func tearDownWithError() throws {
        forceLatinInputSource()
        textEdit.terminate()
        flickey.terminate()
    }

    func testAutomaticCorrectionUndoAndLearnedBlock() throws {
        let textView = try freshDocument()

        // XCUIApplication.launch() returns when the process is idle, but the
        // global event tap is installed only after the async Accessibility trust
        // check. Give that external service a short bounded settling window
        // before judging the first keystrokes of a fresh process.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        func typeWrongRun() {
            textView.click()
            textEdit.typeKey("a", modifierFlags: .command)
            textEdit.typeKey(.delete, modifierFlags: [])
            forceLatinInputSource()
            textView.typeText("akuo akuo ")
        }
        func corrected() -> Bool {
            (textView.value as? String)?.contains("שלום שלום") == true
        }
        func undo() {
            doubleTapOption()
            XCTAssertTrue(waitUntil(timeout: 5) {
                (textView.value as? String)?.lowercased().contains("akuo akuo") == true
            }, "double-Option should restore the original run")
            XCTAssertTrue(waitForSource(abc, 5), "undo should restore the previous input source")
        }

        step("Two confident wrong-layout words should auto-correct")
        typeWrongRun()
        XCTAssertTrue(waitUntil(timeout: 15, corrected),
                      "automatic correction should replace the two-word run; got \(textView.value ?? "nil"), source \(currentInputSourceID())")
        XCTAssertTrue(waitForSource(hebrew, 5))

        step("Reject the correction with double-Option")
        undo()

        step("A second rejection teaches the exception")
        typeWrongRun()
        XCTAssertTrue(waitUntil(timeout: 10, corrected))
        undo()

        step("The learned word must no longer auto-correct")
        typeWrongRun()
        XCTAssertFalse(waitUntil(timeout: 3, corrected),
                       "a twice-rejected word should remain untouched")
        XCTAssertEqual(currentInputSourceID(), abc)
    }

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
        textEdit.typeKey("a", modifierFlags: .command)
        textEdit.typeKey(.delete, modifierFlags: [])
        return textView
    }
}
