import XCTest
import AppKit

// LIVE browser integration test: drives real Safari and asserts the system
// keyboard input source actually flips for a website. (It does NOT switch tabs
// — that variant was too flaky; this navigates a single tab + re-activates.)
//
// Flow:
//   • setUp: force the keyboard to Latin (ABC); launch FlicKey with an ISOLATED
//     settings store seeded { localhost → <non-Latin layout> }; launch Safari.
//   • test: navigate the tab to localhost; switch away to Finder and back to
//     Safari (so FlicKey re-reads the active tab); then poll the live keyboard,
//     expecting it to flip to the non-Latin layout.
//
// This is the flaky frontier: it depends on page-load timing, FlicKey's
// AppleScript URL read, app-activation events, and granted permissions. It
// controls Safari. Skips cleanly if the machine lacks two enabled layouts.
final class BrowserIntegrationUITests: XCTestCase {

    private var flickey: XCUIApplication!
    private var safari: XCUIApplication!
    private var latin = ""
    private var other = ""
    private var web: LocalWebServer!
    private let siteOne = "localhost"
    private let siteTwo = "127.0.0.1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let pair = twoEnabledLayouts() else {
            throw XCTSkip("Needs two enabled keyboard layouts (e.g. ABC + Hebrew).")
        }
        (latin, other) = pair
        web = try LocalWebServer()
        forceLatinInputSource()
        step("Seed \(siteOne) → \(other); launch FlicKey (isolated store) + Safari")

        // Safari restores its previous tab across launches. Put it on a neutral
        // page before FlicKey starts; otherwise the setup-time Latin reset is a
        // legitimate manual change on yesterday's restored site and overwrites
        // that site's seed.
        let existingSafari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        if existingSafari.state != .notRunning { existingSafari.terminate() }
        safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        safari.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        safari.launch()
        safari.typeKey("l", modifierFlags: .command)
        safari.typeText("about:blank\r")
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        forceLatinInputSource()

        // Seed the named loopback host → the non-Latin layout (and the numeric
        // loopback host → Latin, for the tab-switch test). We start in Latin and navigate; only FlicKey
        // could set the non-Latin layout, so a flip proves the live per-site
        // pipeline end to end.
        flickey = XCUIApplication()
        flickey.launchArguments = [
            "-uiTestReset",
            "-diagRecordEnabled", "YES",
            "-uiTestSeedSites", "\(siteOne)=\(other);\(siteTwo)=\(latin)",
        ]
        flickey.launch()
    }

    override func tearDownWithError() throws {
        if safari != nil { safari.terminate() }
        if flickey != nil { flickey.terminate() }
    }

    func testNavigatingToASiteFlipsTheKeyboard() {
        step("Open \(siteOne) in Safari")
        navigate(to: siteOne)
        XCTAssertTrue(waitForActiveSite(siteOne), "FlicKey should resolve Safari's active site")

        // Use the app-activation path (reliable) rather than same-tab AX title
        // detection (flaky in the harness): force Latin, switch away, then
        // re-activate Safari so FlicKey re-reads the active tab.
        step("Force the keyboard to Latin, then re-activate Safari to re-trigger FlicKey")
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        forceLatinInputSource() // do not teach the active site the test's reset value
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        safari.activate()

        step("On Safari re-activation FlicKey reads \(siteOne) → should FLIP the keyboard to \(other)")
        XCTAssertTrue(waitForSource(other, 20),
                      "re-activating Safari on \(siteOne) should flip to \(other); current=\(currentInputSourceID())")
        step("Result: keyboard is now \(currentInputSourceID())")
    }

    // QA C2 — the two-tabs flow: each tab remembers its own language and
    // switching tabs flips the keyboard. Tab switches are detected via the
    // window-title change, so the two local fixtures have different page titles.
    //
    // Ordering matters: the LATIN-seeded tab is set up first, and after the
    // non-Latin seed has been applied the test never changes the layout itself.
    // (Changing it would be a real input change on the then-current site and
    // FlicKey would dutifully re-learn it — overwriting the seed. v1 of this
    // test did exactly that via navigate()'s forceLatin and poisoned itself.)
    func testSwitchingTabsFlipsTheKeyboardPerSite() {
        step("Tab 1: open \(siteTwo) (seeded → \(latin))")
        navigate(to: siteTwo)
        XCTAssertTrue(waitForActiveSite(siteTwo), "FlicKey should resolve the first Safari tab")

        step("Tab 2: ⌘T, open \(siteOne) (seeded → \(other)) — the load itself should flip")
        safari.typeKey("t", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        navigate(to: siteOne)
        XCTAssertTrue(waitForActiveSite(siteOne), "FlicKey should resolve the second Safari tab")
        // Pure title-change detection: no app re-activation crutch.
        XCTAssertTrue(waitForSource(other, 20),
                      "loading \(siteOne) in the active tab should flip to \(other); current=\(currentInputSourceID())")

        step("⌃⇧⇥ to tab 1 (\(siteTwo)) → keyboard should flip back to \(latin)")
        safari.typeKey(.tab, modifierFlags: [.control, .shift])   // previous tab
        XCTAssertTrue(waitForActiveSite(siteTwo), "FlicKey should observe the previous Safari tab")
        XCTAssertTrue(waitForSource(latin, 20),
                      "tab 1 (\(siteTwo)) should flip back to \(latin); current=\(currentInputSourceID())")

        step("⌃⇥ to tab 2 (\(siteOne)) → keyboard should flip to \(other)")
        safari.typeKey(.tab, modifierFlags: .control)             // next tab
        XCTAssertTrue(waitForActiveSite(siteOne), "FlicKey should observe the next Safari tab")
        XCTAssertTrue(waitForSource(other, 20),
                      "tab 2 (\(siteOne)) should flip to \(other); current=\(currentInputSourceID())")
    }

    func testLearnsAndRecallsASiteWithoutSeedingItsValue() {
        flickey.terminate()
        flickey.launchArguments = ["-uiTestReset", "-diagRecordEnabled", "YES"]
        flickey.launch()

        step("Visit \(siteOne) and choose \(other) manually")
        navigate(to: siteOne)
        XCTAssertTrue(waitForActiveSite(siteOne), "FlicKey should resolve the site being learned")
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        safari.activate()   // establish site one as the active memory key
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        selectInputSource(id: other)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        step("Open a new tab, choose Latin there, then return to \(siteOne)")
        safari.activate()
        postPhysicalShortcut(keyCode: 17, flags: .maskCommand) // physical ⌘T
        XCTAssertTrue(waitForActiveSite("New Tab"),
                      "FlicKey should leave the learned site before changing layout")
        selectInputSource(id: latin)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        postPhysicalShortcut(keyCode: 48, flags: [.maskControl, .maskShift])
        XCTAssertTrue(waitForActiveSite(siteOne), "FlicKey should resolve the learned site on return")
        XCTAssertTrue(waitForSource(other, 20),
                      "returning to a learned site should restore \(other); current=\(currentInputSourceID())")
    }

    // MARK: - helpers

    private func navigate(to host: String, forceLatinBeforeTyping: Bool = true) {
        step("  · typing \(web.url(host)) into Safari's address bar")
        if forceLatinBeforeTyping { forceLatinInputSource() }
        safari.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        safari.typeKey("l", modifierFlags: .command)    // focus the address bar
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        // Paste inside the isolated guest so URL entry is independent of the
        // active keyboard layout. Tart clipboard sharing remains disabled.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(web.url(host), forType: .string)
        safari.typeKey("v", modifierFlags: .command)
        safari.typeKey(.return, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))   // let it load
    }

    private func waitForActiveSite(_ host: String, timeout: TimeInterval = 10) -> Bool {
        let statusItem = flickey.statusItems["flickeyStatusItem"]
        guard statusItem.waitForExistence(timeout: 5) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            statusItem.click()
            let found = flickey.menuItems["Site: \(host)"].exists
            flickey.typeKey(.escape, modifierFlags: [])
            safari.activate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if found { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

}

// Opt-in Firefox counterpart to the Safari test above. Firefox has no usable
// AppleScript tab vocabulary, so this exercises the Gecko AXWebArea → AXURL path
// end to end. Kept out of the default UI run for the same live-browser timing
// reasons as Safari, and skipped on machines without Firefox installed.
final class FirefoxBrowserIntegrationUITests: XCTestCase {

    private var flickey: XCUIApplication!
    private var firefox: XCUIApplication!
    private var latin = ""
    private var other = ""
    private var web: LocalWebServer!
    private let siteOne = "localhost"
    private let siteTwo = "127.0.0.1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox") != nil else {
            throw XCTSkip("Firefox is not installed.")
        }
        guard let pair = twoEnabledLayouts() else {
            throw XCTSkip("Needs two enabled keyboard layouts (e.g. ABC + Hebrew).")
        }
        (latin, other) = pair
        web = try LocalWebServer()
        forceLatinInputSource()
        step("Seed \(siteOne) → \(other); launch FlicKey (isolated store) + Firefox")

        // A release build may already be running as the user's menu-bar agent.
        // It shares the product bundle ID and prevents XCUITest from launching
        // this run's debug build unless it is stopped first.
        let existingFlicKey = XCUIApplication(bundleIdentifier: "com.talalfi.FlicKey")
        if existingFlicKey.state != .notRunning { existingFlicKey.terminate() }
        let existingFirefox = XCUIApplication(bundleIdentifier: "org.mozilla.firefox")
        if existingFirefox.state != .notRunning { existingFirefox.terminate() }

        flickey = XCUIApplication()
        flickey.launchArguments = [
            "-uiTestReset",
            "-diagRecordEnabled", "YES",
            "-uiTestSeedSites", "\(siteOne)=\(other);\(siteTwo)=\(latin)",
        ]
        flickey.launch()

        // The live reader cannot work until this exact debug build has an
        // Accessibility grant. Detect the app's own permission alert and skip
        // with a useful reason instead of timing out while Firefox is blocked.
        if flickey.staticTexts["Accessibility Access Required"].waitForExistence(timeout: 2) {
            throw XCTSkip("Grant Accessibility access to the debug FlicKey build, then rerun.")
        }

        firefox = XCUIApplication(bundleIdentifier: "org.mozilla.firefox")
        firefox.launch()
    }

    override func tearDownWithError() throws {
        if firefox != nil, firefox.state != .notRunning { firefox.terminate() }
        if flickey != nil, flickey.state != .notRunning { flickey.terminate() }
    }

    func testNavigatingToASiteFlipsTheKeyboard() {
        step("Open \(siteOne) in Firefox")
        navigate(to: siteOne)

        step("Force Latin, switch away, then reactivate Firefox")
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        forceLatinInputSource() // do not teach the active site the test's reset value
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        firefox.activate()

        step("Firefox AXURL resolves \(siteOne) → keyboard should flip to \(other)")
        XCTAssertTrue(waitForSource(other, 20),
                      "re-activating Firefox on \(siteOne) should flip to \(other); current=\(currentInputSourceID())")
    }

    func testSwitchingTabsFlipsTheKeyboardPerSite() {
        step("Tab 1: open \(siteTwo) (seeded → \(latin))")
        navigate(to: siteTwo)

        step("Tab 2: ⌘T, open \(siteOne) (seeded → \(other))")
        firefox.typeKey("t", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        navigate(to: siteOne)
        XCTAssertTrue(waitForSource(other, 20),
                      "loading \(siteOne) should flip to \(other); current=\(currentInputSourceID())")

        step("⌃⇧⇥ to \(siteTwo) → keyboard should flip to \(latin)")
        firefox.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForSource(latin, 20),
                      "\(siteTwo) should flip to \(latin); current=\(currentInputSourceID())")

        step("⌃⇥ to \(siteOne) → keyboard should flip to \(other)")
        firefox.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitForSource(other, 20),
                      "\(siteOne) should flip to \(other); current=\(currentInputSourceID())")
    }

    private func navigate(to host: String) {
        forceLatinInputSource()
        firefox.typeKey("l", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(web.url(host), forType: .string)
        firefox.typeKey("v", modifierFlags: .command)
        firefox.typeKey(.return, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }
}
