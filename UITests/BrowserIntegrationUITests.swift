import XCTest

// LIVE browser integration test: drives real Safari and asserts the system
// keyboard input source actually flips for a website. (It does NOT switch tabs
// — that variant was too flaky; this navigates a single tab + re-activates.)
//
// Flow:
//   • setUp: force the keyboard to Latin (ABC); launch FlicKey with an ISOLATED
//     settings store seeded { example.com → <non-Latin layout> }; launch Safari.
//   • test: navigate the tab to example.com; switch away to Finder and back to
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

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let pair = twoEnabledLayouts() else {
            throw XCTSkip("Needs two enabled keyboard layouts (e.g. ABC + Hebrew).")
        }
        (latin, other) = pair
        forceLatinInputSource()
        step("Seed example.com → \(other); launch FlicKey (isolated store) + Safari")

        // Seed example.com → the non-Latin layout (and iana.org → Latin, for
        // the tab-switch test). We start in Latin and navigate; only FlicKey
        // could set the non-Latin layout, so a flip proves the live per-site
        // pipeline end to end.
        flickey = XCUIApplication()
        flickey.launchArguments = [
            "-uiTestReset",
            "-uiTestSeedSites", "example.com=\(other);iana.org=\(latin)",
        ]
        flickey.launch()

        safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        safari.launch()
    }

    override func tearDownWithError() throws {
        safari.terminate()
        flickey.terminate()
    }

    func testNavigatingToASiteFlipsTheKeyboard() {
        step("Open example.com in Safari")
        navigate(to: "example.com")

        // Use the app-activation path (reliable) rather than same-tab AX title
        // detection (flaky in the harness): force Latin, switch away, then
        // re-activate Safari so FlicKey re-reads the active tab.
        step("Force the keyboard to Latin, then re-activate Safari to re-trigger FlicKey")
        forceLatinInputSource()
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        safari.activate()

        step("On Safari re-activation FlicKey reads example.com → should FLIP the keyboard to \(other)")
        XCTAssertTrue(waitForSource(other, 20),
                      "re-activating Safari on example.com should flip to \(other); current=\(currentInputSourceID())")
        step("Result: keyboard is now \(currentInputSourceID())")
    }

    // QA C2 — the two-tabs flow: each tab remembers its own language and
    // switching tabs flips the keyboard. Tab switches are detected via the
    // window-title change, so the two sites must have DIFFERENT page titles
    // (example.com and example.org share "Example Domain" — hence iana.org).
    //
    // Ordering matters: the LATIN-seeded tab is set up first, and after the
    // non-Latin seed has been applied the test never changes the layout itself.
    // (Changing it would be a real input change on the then-current site and
    // FlicKey would dutifully re-learn it — overwriting the seed. v1 of this
    // test did exactly that via navigate()'s forceLatin and poisoned itself.)
    func testSwitchingTabsFlipsTheKeyboardPerSite() {
        step("Tab 1: open iana.org (seeded → \(latin))")
        navigate(to: "iana.org")

        step("Tab 2: ⌘T, open example.com (seeded → \(other)) — the load itself should flip")
        safari.typeKey("t", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        navigate(to: "example.com")
        // Pure title-change detection: no app re-activation crutch.
        XCTAssertTrue(waitForSource(other, 20),
                      "loading example.com in the active tab should flip to \(other); current=\(currentInputSourceID())")

        step("⌃⇧⇥ to tab 1 (iana.org) → keyboard should flip back to \(latin)")
        safari.typeKey(.tab, modifierFlags: [.control, .shift])   // previous tab
        XCTAssertTrue(waitForSource(latin, 20),
                      "tab 1 (iana.org) should flip back to \(latin); current=\(currentInputSourceID())")

        step("⌃⇥ to tab 2 (example.com) → keyboard should flip to \(other)")
        safari.typeKey(.tab, modifierFlags: .control)             // next tab
        XCTAssertTrue(waitForSource(other, 20),
                      "tab 2 (example.com) should flip to \(other); current=\(currentInputSourceID())")
    }

    // MARK: - helpers

    private func navigate(to host: String) {
        step("  · typing http://\(host) into Safari's address bar")
        forceLatinInputSource()                         // type the URL in Latin
        safari.typeKey("l", modifierFlags: .command)    // focus the address bar
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        safari.typeText("http://\(host)\r")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))   // let it load
    }

}
