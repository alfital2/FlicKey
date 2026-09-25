import AppKit
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
            "-uiTestDisableRememberVisitedApps",
            "-uiTestSeedAppRules", "TextEdit=\(other);Calculator=\(latin)",
        ]
        flickey.launch()
        textEdit.launch()
        calculator.launch()

        step("Focus TextEdit → expect \(other)")
        textEdit.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        }, "TextEdit never became frontmost")
        XCTAssertTrue(waitForSource(other, 10),
                      "TextEdit is forced to \(other); current=\(currentInputSourceID())")

        step("Focus Calculator → expect \(latin)")
        calculator.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.calculator"
        }, "Calculator never became frontmost")
        XCTAssertTrue(waitForSource(latin, 10),
                      "Calculator is forced to \(latin); current=\(currentInputSourceID())")

        step("Back to TextEdit → expect \(other) again")
        textEdit.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        }, "TextEdit never became frontmost on return")
        XCTAssertTrue(waitForSource(other, 10),
                      "returning to TextEdit should flip back; current=\(currentInputSourceID())")
    }

    // QA B3 — the preservation guarantee: apps with NO rule must leave the
    // user's layout alone, both when hopping away and when coming back.
    func testUnforcedAppsPreserveTheUsersLayout() {
        step("No rules seeded; launch everything")
        flickey.launchArguments = ["-uiTestReset", "-uiTestDisableRememberVisitedApps"]
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

    // Customer scenario: Terminal is pinned to English while other apps use
    // Russian PC and a third layout. Repeat activations to catch missed events.
    func testTerminalPinnedToEnglishAcrossThreeLayouts() throws {
        let russianPC = "com.apple.keylayout.RussianWin"
        let hebrewPC = "com.apple.keylayout.Hebrew-PC"
        guard inputSourceName(id: russianPC) != nil,
              inputSourceName(id: hebrewPC) != nil else {
            throw XCTSkip("Needs Russian PC and Hebrew PC enabled with ABC")
        }
        let terminal = XCUIApplication(bundleIdentifier: "com.apple.Terminal")
        defer { terminal.terminate() }

        flickey.launchArguments = [
            "-uiTestReset", "-uiTestDisableRememberVisitedApps",
            "-diagRecordEnabled", "YES",
            "-uiTestSeedAppRules", "Terminal=\(latin)",
        ]
        flickey.launch() // auto-fix stays off in the reset, isolated store
        textEdit.launch()
        terminal.launch()

        for visit in 1...12 {
            let away = visit.isMultiple(of: 2) ? hebrewPC : russianPC
            step("Visit \(visit): choose \(away) in TextEdit, then enter pinned Terminal")
            textEdit.activate()
            XCTAssertTrue(waitUntil(timeout: 3) {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
            }, "TextEdit never became frontmost on visit \(visit)")
            selectInputSource(id: away)
            XCTAssertTrue(waitForSource(away, 3), "could not select \(away)")
            terminal.activate()
            XCTAssertTrue(waitUntil(timeout: 3) {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal"
            }, "Terminal never became frontmost on visit \(visit)")
            XCTAssertTrue(waitForSource(latin, 5),
                          "Terminal did not restore English on visit \(visit); current=\(currentInputSourceID())")
            // An early ABC observation is insufficient: macOS can finish the
            // previous app's selection after FlicKey has already selected ABC.
            pause(0.95)
            XCTAssertEqual(currentInputSourceID(), latin,
                           "Terminal lost English after settling on visit \(visit)")
        }

        step("Relaunch FlicKey with the isolated rule preserved")
        flickey.terminate()
        flickey.launchArguments = ["-uiTestPreserveState", "-uiTestDisableRememberVisitedApps"]
        flickey.launch()
        textEdit.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        }, "TextEdit never became frontmost after FlicKey relaunch")
        selectInputSource(id: russianPC)
        XCTAssertTrue(waitForSource(russianPC, 3))
        terminal.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal"
        }, "Terminal never became frontmost after FlicKey relaunch")
        XCTAssertTrue(waitForSource(latin, 5),
                      "Terminal's English rule did not survive relaunch")
        pause(0.95)
        XCTAssertEqual(currentInputSourceID(), latin,
                       "Terminal lost English after relaunch settled")
    }

    // Deterministically reproduce the late system selection seen in the
    // customer trace: the previous app's layout wins after Terminal activates.
    func testTerminalReassertsEnglishAfterLateLayoutSelection() throws {
        let russianPC = "com.apple.keylayout.RussianWin"
        guard inputSourceName(id: russianPC) != nil else {
            throw XCTSkip("Needs Russian PC enabled with ABC")
        }
        let terminal = XCUIApplication(bundleIdentifier: "com.apple.Terminal")
        defer { terminal.terminate() }

        flickey.launchArguments = [
            "-uiTestReset", "-uiTestDisableRememberVisitedApps",
            "-uiTestSeedAppRules", "Terminal=\(latin)",
        ]
        flickey.launch()
        textEdit.launch()
        terminal.launch()

        textEdit.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        })
        selectInputSource(id: russianPC)
        XCTAssertTrue(waitForSource(russianPC, 3))

        terminal.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal"
        })
        XCTAssertTrue(waitForSource(latin, 5))
        step("Deliver the previous app's Russian selection after Terminal is frontmost")
        selectInputSource(id: russianPC)
        XCTAssertTrue(waitForSource(latin, 3),
                      "Terminal did not recover from a late Russian selection")
        pause(0.95)
        XCTAssertEqual(currentInputSourceID(), latin,
                       "Terminal did not keep English after the handoff settled")
    }

    func testTerminalHandoffDoesNotOverrideNextAppsLayout() throws {
        let russianPC = "com.apple.keylayout.RussianWin"
        let hebrewPC = "com.apple.keylayout.Hebrew-PC"
        guard inputSourceName(id: russianPC) != nil,
              inputSourceName(id: hebrewPC) != nil else {
            throw XCTSkip("Needs Russian PC and Hebrew PC enabled with ABC")
        }
        let terminal = XCUIApplication(bundleIdentifier: "com.apple.Terminal")
        defer { terminal.terminate() }

        flickey.launchArguments = [
            "-uiTestReset", "-uiTestDisableRememberVisitedApps",
            "-uiTestSeedAppRules", "Terminal=\(latin)",
        ]
        flickey.launch()
        textEdit.launch()
        terminal.launch()

        textEdit.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        })
        selectInputSource(id: russianPC)
        XCTAssertTrue(waitForSource(russianPC, 3))

        terminal.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal"
        })
        XCTAssertTrue(waitForSource(latin, 5))

        step("Leave Terminal and choose Hebrew in unforced TextEdit")
        textEdit.activate()
        XCTAssertTrue(waitUntil(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        })
        selectInputSource(id: hebrewPC)
        XCTAssertTrue(waitForSource(hebrewPC, 3))
        pause(1.0)
        XCTAssertEqual(currentInputSourceID(), hebrewPC,
                       "Terminal's delayed checks changed the next app's layout")
    }
}
