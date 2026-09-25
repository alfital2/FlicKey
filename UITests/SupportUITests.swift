import XCTest

// UI tests for the Settings → Support tab (trial status, license entry, bug
// report). Under -uiTestReset the app uses .uitest Keychain items and resets
// the trial at launch, so these always start deterministically: unlicensed,
// "Free trial - 30 days left." — and can never touch the user's real
// trial/license state. The only Activate click here uses an EMPTY key, which
// the app rejects locally (no network, no Keychain write).
final class SupportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        forceLatinInputSource()
        app = XCUIApplication()
        app.launchArguments = ["-uiTestOpenSettings", "-uiTestReset",
                               "-uiTestSettingsTab", "Support"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }


    private func openSupportTab() {
        XCTAssertTrue(app.windows["Support"].waitForExistence(timeout: 10),
                      "Settings should open directly on Support")
    }

    // The isolated, freshly-reset trial must begin with all 30 days left.
    func testFreshTrialStatusIsShown() {
        step("Support tab — expect the fresh-trial status line")
        openSupportTab()
        let status = app.descendants(matching: .any).matching(identifier: "licenseStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), "status line should exist")
        XCTAssertEqual(status.value as? String, "Free trial - 30 days left.",
                       "isolated UI-test trial should always start with 30 days left")
    }

    // Unlicensed state: key entry + Activate + Support visible, Remove hidden.
    func testUnlicensedStateShowsEntryAndSupportControls() {
        step("Support tab — unlicensed: key field, Activate, Support; no Remove")
        openSupportTab()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "licenseKeyField").firstMatch
            .waitForExistence(timeout: 10),
                      "license key field should be visible when unlicensed")
        XCTAssertTrue(app.buttons["activateLicense"].exists, "Activate should be visible")
        XCTAssertTrue(app.buttons["buyLicense"].exists, "buy button should be visible")
        XCTAssertFalse(app.buttons["Remove License"].exists,
                       "Remove License must be hidden when unlicensed")
        // Report a Bug moved to the Improve tab; it must NOT be on Support.
        XCTAssertFalse(app.buttons["reportBug"].exists, "Report a Bug should not be on the Support tab")
    }

    // Activating with an empty key is rejected locally with a hint overlay
    // (and must not get stuck on the "Checking your license…" state).
    func testActivateWithEmptyKeyShowsHint() {
        step("Click Activate with an empty key — expect the 'Enter your license key.' hint")
        openSupportTab()
        let activate = app.buttons["activateLicense"]
        XCTAssertTrue(activate.waitForExistence(timeout: 10))

        activate.click()
        XCTAssertTrue(app.staticTexts["Enter your license key."].waitForExistence(timeout: 4),
                      "the empty-key hint overlay should appear")

        // The status line must settle back to the trial text, and Activate
        // must be re-enabled for another attempt.
        let status = app.descendants(matching: .any).matching(identifier: "licenseStatus").firstMatch
        XCTAssertTrue(waitUntil(timeout: 4) {
            (status.value as? String)?.hasPrefix("Free trial") == true
        }, "status should return to the trial line after the failed attempt")
        XCTAssertTrue(waitUntil(timeout: 4) { activate.isEnabled },
                      "Activate should be re-enabled after the failed attempt")
    }

    func testExpiredTrialShowsPaywallAndLicenseEntry() {
        step("Launch as expired — expect the paywall and a way to enter a license")
        app.terminate()
        app.launchArguments.append("-simulateExpired")
        app.launch()

        XCTAssertTrue(app.staticTexts["Your free trial has ended"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Unlock FlicKey"].exists)
        XCTAssertTrue(app.buttons["Enter a License Key"].exists)
        let status = app.descendants(matching: .any).matching(identifier: "licenseStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.value as? String, "Your free trial has ended.")
    }

    func testExpiredTrialLeavesWrongLayoutTextUntouched() throws {
        guard let pair = twoEnabledLayouts(),
              pair.latin == "com.apple.keylayout.ABC",
              pair.other == "com.apple.keylayout.Hebrew-PC" else {
            throw XCTSkip("Needs ABC and Hebrew-PC for the conversion gate check")
        }
        step("Expired trial — double Shift must leave TextEdit unchanged")
        app.terminate()
        app.launchArguments.append("-simulateExpired")
        app.launch()
        XCTAssertTrue(app.staticTexts["Your free trial has ended"].waitForExistence(timeout: 10))

        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                                    "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        textEdit.launch()
        defer { textEdit.terminate() }
        var field = textEdit.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            textEdit.typeKey("n", modifierFlags: .command)
            field = textEdit.textViews.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        textEdit.typeKey("a", modifierFlags: .command)
        textEdit.typeKey(.delete, modifierFlags: [])
        field.typeText("akuo")
        XCTAssertEqual(field.value as? String, "akuo")
        doubleTapShift()
        XCTAssertFalse(waitUntil(timeout: 2) { (field.value as? String) == "שלום" })
        XCTAssertEqual(field.value as? String, "akuo")
    }
}
