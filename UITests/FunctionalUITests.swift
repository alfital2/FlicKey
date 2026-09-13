import XCTest

// UI automation for the genuinely-automatable product flows (no real
// browser/Teams/permissions needed): the Apps add→remove lifecycle and the
// shortcut recorder. These drive the real Settings UI and self-clean so they
// don't pollute the user's saved settings.
final class FunctionalUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        forceLatinInputSource()
        app = XCUIApplication()
        app.launchArguments = ["-uiTestOpenSettings", "-uiTestReset"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }


    // QA E2 + E7-ish + E1 (UI portion): add an app by name, then remove it.
    func testAddThenRemoveAnApp() {
        step("Apps tab → type 'Calculator', add it, then right-click → Remove")
        app.tab("Apps").click()
        let field = app.textFields["Add app by name…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        // Add "Calculator" (installed on every Mac, not a built-in default).
        field.click()
        field.typeText("Calculator\r")   // Return triggers add-by-name

        let row = app.staticTexts["Calculator"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Calculator row should appear after adding")

        // Remove via the row's right-click context menu.
        row.rightClick()
        let remove = app.menuItems["Remove Calculator"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "context menu should offer Remove")
        remove.click()

        XCTAssertFalse(app.staticTexts["Calculator"].waitForExistence(timeout: 4),
                       "Calculator row should be gone after removal")
    }

    // The complete user story: configure through Settings, observe the real
    // app switch, remove the rule, and prove the app is unmanaged again.
    func testAppRuleFullLifecycleAffectsTheRealApp() throws {
        guard let pair = twoEnabledLayouts(), let otherName = inputSourceName(id: pair.other) else {
            throw XCTSkip("Needs two enabled keyboard layouts")
        }
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        defer { calculator.terminate(); forceLatinInputSource() }

        app.tab("Apps").click()
        let field = app.textFields["addAppByName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click(); field.typeText("Calculator\r")

        let popup = app.popUpButtons["appRule.Calculator"]
        XCTAssertTrue(popup.waitForExistence(timeout: 5), "Calculator should expose its rule picker")
        popup.click()
        let forced = app.menuItems["Always: \(otherName)"]
        XCTAssertTrue(forced.waitForExistence(timeout: 3))
        forced.click()

        step("Activate Calculator — the Settings choice should take effect")
        calculator.launch()
        calculator.activate()
        XCTAssertTrue(waitForSource(pair.other, 10),
                      "Calculator should use the layout selected through Settings")

        step("Remove Calculator, then prove it no longer forces a layout")
        app.activate()
        let row = app.staticTexts["appRuleName.Calculator"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["Remove Calculator"].click()
        XCTAssertFalse(popup.waitForExistence(timeout: 3))

        forceLatinInputSource()
        calculator.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        XCTAssertEqual(currentInputSourceID(), pair.latin,
                       "after removal Calculator must leave the user's layout unchanged")
    }

    // QA E6: adding an already-listed app shows a notice and doesn't duplicate.
    func testAddingDuplicateIsRejected() {
        step("Add 'Calculator' twice — the duplicate should be rejected")
        app.tab("Apps").click()
        let field = app.textFields["Add app by name…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.click(); field.typeText("Calculator\r")
        XCTAssertTrue(app.staticTexts["Calculator"].waitForExistence(timeout: 5))

        // Add the same one again (should be rejected as already listed).
        field.click(); field.typeText("Calculator\r")

        // Behavioral dedup check: a single Remove must clear it entirely. If the
        // duplicate add had created a second row, one would survive the remove.
        app.staticTexts["Calculator"].rightClick()
        app.menuItems["Remove Calculator"].click()
        XCTAssertFalse(app.staticTexts["Calculator"].waitForExistence(timeout: 3),
                       "one Remove clears it → the duplicate add did not create a 2nd row")
    }

    // QA F1 + F3: record a new shortcut, then reset to the default (⇧⇧).
    func testRecordThenResetShortcut() {
        step("Record a new shortcut (⌃⌥9), then Reset to default ⇧⇧")
        app.tab("Shortcut").click()
        let current = app.staticTexts["currentShortcut"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let before = current.value as? String

        app.buttons["recordShortcut"].click()
        app.typeKey("9", modifierFlags: [.control, .option])   // record ⌃⌥9
        // The displayed current shortcut should have changed.
        XCTAssertTrue(waitUntil(timeout: 4) { (current.value as? String) != before },
                      "recording should change the displayed shortcut")

        app.buttons["resetShortcut"].click()
        // Re-resolve the element: AppKit updates this label in place, while an
        // XCUIElement captured before the recorder's refresh can retain a stale
        // accessibility snapshot after the second state change.
        XCTAssertTrue(waitUntil(timeout: 4) {
            (app.staticTexts["currentShortcut"].value as? String) == "⇧⇧"
        },
                      "reset should restore the default ⇧⇧")
        XCTAssertEqual(app.radioButtons["triggerDoubleShift"].value as? Int, 1,
                       "reset should select the double-Shift preset")
    }

    // QA F4: a bare key (no modifier) is rejected during recording.
    func testBareKeyDuringRecordingIsRejected() {
        step("Start recording, press a bare key — it should be ignored")
        app.tab("Shortcut").click()
        let current = app.staticTexts["currentShortcut"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let before = current.value as? String

        app.buttons["recordShortcut"].click()
        app.typeText("a")              // no modifier → should be ignored
        // Pump for a moment so the key event is definitely processed — asserting
        // immediately could pass before the app even saw the key.
        XCTAssertFalse(waitUntil(timeout: 1.5) { (current.value as? String) != before },
                       "bare key should not set a shortcut")
        app.typeKey(.escape, modifierFlags: [])   // cancel recording
    }

    // QA F5: Esc cancels recording and leaves the shortcut unchanged. Verified
    // behaviorally (a chord typed AFTER Esc must not be recorded) — button
    // titles with glyphs get mangled AX labels, so we can't read the armed text.
    func testEscCancelsRecording() {
        step("Start recording, press Esc, then ⌃⌥7 — the chord must NOT be recorded")
        app.tab("Shortcut").click()
        let current = app.staticTexts["currentShortcut"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let before = current.value as? String

        app.buttons["recordShortcut"].click()              // arm the recorder
        app.typeKey(.escape, modifierFlags: [])            // Esc → should cancel
        app.typeKey("7", modifierFlags: [.control, .option])  // recorded only if still armed
        XCTAssertFalse(waitUntil(timeout: 1.5) { (current.value as? String) != before },
                       "Esc should have cancelled recording — ⌃⌥7 must not become the shortcut")
    }

    // QA E5: an unknown app name shows a notice (overlay) and adds nothing.
    func testUnknownAppNameShowsNotice() {
        step("Apps tab → type a nonsense app name — expect a 'No app named…' notice")
        app.tab("Apps").click()
        let field = app.textFields["Add app by name…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.click()
        field.typeText("ZzNoSuchAppQq\r")

        // Exact label match (identifier-or-label subscript), same as the proven
        // license-overlay lookup. The app keeps overlays up longer under
        // -uiTestReset so the ~1 Hz existence poll can't miss the window.
        let notice = app.staticTexts["No app named “ZzNoSuchAppQq”"]
        XCTAssertTrue(notice.waitForExistence(timeout: 6),
                      "an overlay should say the app wasn't found")
        XCTAssertFalse(app.staticTexts["ZzNoSuchAppQq"].exists, "nothing should be added")
    }

    // QA E9 (UI portion): the list groups browsers under their own header, and
    // Safari (always installed) is listed there with the per-site AUTO default.
    func testAppsListShowsBrowserSection() {
        step("Apps tab — expect a BROWSERS section with Safari in it")
        app.tab("Apps").click()
        XCTAssertTrue(app.staticTexts["Preferred Input per App"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BROWSERS"].exists, "browsers section header should exist")
        XCTAssertTrue(app.staticTexts["Safari"].exists, "Safari should be listed as a browser")
    }
}
