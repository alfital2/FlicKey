import XCTest

// Per-app switching, live (QA section B): hop between real apps and assert the
// keyboard follows each app's forced rule — and, just as important, that apps
// WITHOUT a rule never touch the layout the user picked (it must survive
// hopping away and back).
//
// Uses TextEdit and Calculator: both ship with macOS and neither has a
// built-in FlicKey rule, so the seeded/unseeded state is fully test-controlled
// (rules are seeded into the isolated store via -uiTestSeedAppRules).
final class AppSwitchingUITests: XCTestCase {

    private var flickey: XCUIApplication!
    private var textEdit: XCUIApplication!
    private var calculator: XCUIApplication!
    private var latin = ""
    private var other = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let pair = twoEnabledLayouts() else {
            throw XCTSkip("Needs two enabled keyboard layouts (e.g. ABC + Hebrew).")
        }
        (latin, other) = pair
        forceLatinInputSource()
        flickey = XCUIApplication()
        textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
    }

    override func tearDownWithError() throws {
        calculator.terminate()
        textEdit.terminate()
        flickey.terminate()
        forceLatinInputSource()
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // QA B1/B2/B5: two apps forced to different languages — the keyboard flips
    // to match each app as the user hops, repeatedly.
    func testHoppingBetweenForcedAppsFlipsTheKeyboard() {
        step("Seed rules: TextEdit → \(other), Calculator → \(latin); launch everything")
        flickey.launchArguments = [
            "-uiTestReset",
            "-uiTestSeedAppRules", "TextEdit=\(other);Calculator=\(latin)",
        ]
        flickey.launch()
        textEdit.launch()
        calculator.launch()

        step("Focus TextEdit → expect \(other)")
        textEdit.activate()
        XCTAssertTrue(waitForSource(other, 10),
                      "TextEdit is forced to \(other); current=\(currentInputSourceID())")

        step("Focus Calculator → expect \(latin)")
        calculator.activate()
        XCTAssertTrue(waitForSource(latin, 10),
                      "Calculator is forced to \(latin); current=\(currentInputSourceID())")

        step("Back to TextEdit → expect \(other) again")
        textEdit.activate()
        XCTAssertTrue(waitForSource(other, 10),
                      "returning to TextEdit should flip back; current=\(currentInputSourceID())")
    }

    // QA B3 — the preservation guarantee: apps with NO rule must leave the
    // user's layout alone, both when hopping away and when coming back.
    func testUnforcedAppsPreserveTheUsersLayout() {
        step("No rules seeded; launch everything")
        flickey.launchArguments = ["-uiTestReset"]
        flickey.launch()
        textEdit.launch()
        calculator.launch()

        step("In TextEdit, the user picks \(other)")
        textEdit.activate()
        pause(1.0)
        selectInputSource(id: other)
        pause(1.0)

        step("Hop to Calculator — FlicKey must NOT touch the layout")
        calculator.activate()
        pause(2.5)   // observation window: a wrong flip would happen in here
        XCTAssertEqual(currentInputSourceID(), other,
                       "an app with no rule must preserve the user's layout")

        step("Hop back to TextEdit — still preserved")
        textEdit.activate()
        pause(2.5)
        XCTAssertEqual(currentInputSourceID(), other,
                       "the layout must survive hopping away and back")
    }
}
