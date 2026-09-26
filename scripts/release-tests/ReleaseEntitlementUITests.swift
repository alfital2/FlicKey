import XCTest
import AppKit

// Opt-in gate for the exact Developer ID-signed Release artifact. Copy this
// into the disposable VM's UITests before building the runner. Never run on
// the developer's Mac: these fixtures use the real production defaults domain.
final class ReleaseEntitlementUITests: XCTestCase {
    private var app: XCUIApplication!
    private var textEdit: XCUIApplication?
    private let domain = "com.talalfi.FlicKey"

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard NSUserName() == "admin",
              FileManager.default.fileExists(atPath: "/Users/admin/.flickey-test-vm") else {
            throw XCTSkip("Release entitlement gate is VM-only")
        }
        app = XCUIApplication(url: URL(fileURLWithPath: "/Users/admin/ReleaseGate/FlicKey.app"))
        forceLatinInputSource()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        textEdit?.terminate()
        forceLatinInputSource()
    }

    private func checkConversion(enabled: Bool) throws {
        let editor = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit = editor
        editor.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                                  "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        editor.launch()
        let field = editor.textViews.firstMatch
        if !field.waitForExistence(timeout: 4) { editor.typeKey("n", modifierFlags: .command) }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(.delete, modifierFlags: [])
        forceLatinInputSource()
        field.typeText("akuo")
        XCTAssertEqual(field.value as? String, "akuo")
        if enabled {
            XCTAssertTrue(triggerFix(until: { (field.value as? String) == "שלום" }),
                          "Active trial must actually enable conversion")
        } else {
            doubleTapShift()
            XCTAssertFalse(waitUntil(timeout: 2) { (field.value as? String) != "akuo" })
            XCTAssertEqual(field.value as? String, "akuo", "Expired trial must block conversion")
        }
    }

    func testFreshInstallGetsFiniteTrial() throws {
        app.launch()
        if app.buttons["Skip"].waitForExistence(timeout: 3) { app.buttons["Skip"].click() }
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        app.tab("Support").click()
        let status = app.descendants(matching: .any).matching(identifier: "licenseStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Free trial - 30 days left.")
    }

    func testActiveTrialEnablesConversion() throws {
        app.launch()
        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your free trial has ended"].exists)
        try checkConversion(enabled: true)
    }

    func testExpiredTrialBlocksConversionAndOffersPurchase() throws {
        app.launch()
        XCTAssertTrue(app.staticTexts["Your free trial has ended"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Unlock FlicKey"].exists)
        XCTAssertTrue(app.buttons["Enter a License Key"].exists)
        app.buttons["Not now"].click()
        try checkConversion(enabled: false)
    }

    func testReleaseIgnoresTrialResetAndLicensedSimulationArguments() throws {
        app.launchArguments = ["-uiTestReset", "-simulateLicensed", "-simulateGrandfathered", "-simulateTrialFresh"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your free trial has ended"].waitForExistence(timeout: 10))
        app.buttons["Not now"].click()
        try checkConversion(enabled: false)

    }

    func testClockRollbackCannotReviveExpiredTrial() throws {
        app.launch()
        XCTAssertTrue(app.staticTexts["Your free trial has ended"].waitForExistence(timeout: 10))
    }

    func testRunningAppLocksWhenTrialExpires() throws {
        app.launch()
        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your free trial has ended"].exists)
        XCTAssertTrue(app.staticTexts["Your free trial has ended"].waitForExistence(timeout: 75),
                      "Leaving the menu-bar app running must not bypass expiry")
    }
}
