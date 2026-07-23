import XCTest

// Drives the menu-bar status item (QA H2 / H3 / H6): the menu lists Settings…
// and Quit, Settings… opens the window, and Quit really terminates the app.
// The status item can be hidden by menu-bar overflow on small/notched screens,
// so these skip (rather than fail) when it can't be clicked.
final class MenuBarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        forceLatinInputSource()
        app = XCUIApplication()
        // No -uiTestOpenSettings: these tests exercise the menu-bar entry point
        // itself. -uiTestReset still isolates all settings + trial state.
        app.launchArguments = ["-uiTestReset"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if app.state != .notRunning { app.terminate() }
    }

    // Click the status item, or skip if macOS hid it (menu-bar overflow).
    private func openStatusMenu() throws {
        let item = app.statusItems.firstMatch
        guard item.waitForExistence(timeout: 10), item.isHittable else {
            throw XCTSkip("FlicKey's status item isn't clickable (menu-bar overflow?)")
        }
        item.click()
    }

    // QA H2: the menu offers Settings… and Quit.
    func testStatusMenuListsSettingsAndQuit() throws {
        step("Open the status-bar menu — expect Settings… and Quit")
        try openStatusMenu()
        XCTAssertTrue(app.menuItems["Settings…"].waitForExistence(timeout: 5),
                      "menu should offer Settings…")
        XCTAssertTrue(app.menuItems["Quit"].exists, "menu should offer Quit")
        app.typeKey(.escape, modifierFlags: [])   // close the menu
    }

    // QA H3: Settings… opens the Settings window (titled after the first tab).
    func testSettingsMenuItemOpensTheWindow() throws {
        step("Status-bar menu → Settings… — expect the Settings window")
        try openStatusMenu()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        XCTAssertTrue(app.windows["General"].waitForExistence(timeout: 5),
                      "Settings window should open from the menu")
    }

    // QA H6: Quit actually terminates the app (verified by process state, not
    // by trusting the click).
    func testQuitMenuItemTerminatesTheApp() throws {
        step("Status-bar menu → Quit — expect the app process to exit")
        try openStatusMenu()
        let quit = app.menuItems["Quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        quit.click()
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.state == .notRunning },
                      "Quit should terminate FlicKey")
    }
}
