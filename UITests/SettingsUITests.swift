import XCTest

// End-to-end UI tests for the Settings window. Launched with -uiTestOpenSettings
// so the window opens on launch (no need to automate the menu-bar status item).
// These drive the real app, so they take over the screen while running.
final class SettingsUITests: XCTestCase {

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

    // A toolbar tab can surface as a toolbar button, plain button, or radio
    // button depending on macOS version — try each.

    func testSettingsWindowOpensWithTabs() {
        step("Open Settings — expect General / Sound / Shortcut / Apps / Support tabs")
        XCTAssertTrue(app.tab("General").waitForExistence(timeout: 10), "General tab should appear")
        XCTAssertTrue(app.tab("Sound").exists, "Sound tab should exist")
        XCTAssertTrue(app.tab("Shortcut").exists, "Shortcut tab should exist")
        XCTAssertTrue(app.tab("Apps").exists, "Apps tab should exist")
        XCTAssertTrue(app.tab("Support").exists, "Support tab should exist")
    }

    // Find a control by accessibility identifier regardless of whether AppKit
    // exposes NSSwitch as a switch or a checkbox to the accessibility layer.
    private func control(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testGeneralTabHasStartupAndUpdateControls() {
        step("General tab — check Launch-at-login + update controls")
        XCTAssertTrue(control("launchAtLoginSwitch").waitForExistence(timeout: 10))
        XCTAssertTrue(control("autoUpdateSwitch").exists)
        XCTAssertTrue(app.buttons["Check for Updates Now"].exists)
    }

    // The sound popup must be enabled exactly when the click-sound toggle is on.
    func testSoundToggleGatesTheSoundPicker() {
        step("Sound tab — toggle the click-sound switch, expect the picker to follow")
        app.tab("Sound").click()
        let toggle = control("clickSoundSwitch")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "sound toggle should exist")
        let popup = app.popUpButtons["clickSoundPicker"]
        XCTAssertTrue(popup.exists, "sound picker should exist")

        let initiallyOn = (toggle.value as? Int) == 1
        XCTAssertEqual(popup.isEnabled, initiallyOn,
                       "picker enablement should match the toggle")

        toggle.click()
        XCTAssertTrue(waitUntil(timeout: 3) { popup.isEnabled != initiallyOn },
                      "toggling should flip the picker's enablement")
        toggle.click()   // restore
        XCTAssertTrue(waitUntil(timeout: 3) { popup.isEnabled == initiallyOn })
    }

    // The per-layout tap pickers only matter while some cue output (haptic or
    // sound) is on — they must disable when both are off.
    func testLayoutSwitchCueControlsGateTheTapPickers() {
        step("Sound tab — layout-switch cue: toggles exist, per-layout pickers gated on either")
        app.tab("Sound").click()
        let haptic = control("cueHapticSwitch")
        let sound = control("cueSoundSwitch")
        XCTAssertTrue(haptic.waitForExistence(timeout: 10), "cue haptic toggle should exist")
        XCTAssertTrue(sound.exists, "cue sound toggle should exist")

        let picker = app.popUpButtons["tapsPopup"].firstMatch
        XCTAssertTrue(picker.exists, "at least one per-layout tap picker should exist")

        // Fresh isolated store: haptic defaults on, sound off → pickers enabled.
        XCTAssertEqual(haptic.value as? Int, 1, "haptic should default on")
        XCTAssertEqual(sound.value as? Int, 0, "sound should default off")
        XCTAssertTrue(picker.isEnabled, "pickers should be enabled while haptic is on")

        haptic.click()   // both outputs now off
        XCTAssertTrue(waitUntil(timeout: 3) { !picker.isEnabled },
                      "pickers should disable when haptic and sound are both off")

        sound.click()    // sound alone should re-enable them
        XCTAssertTrue(waitUntil(timeout: 3) { picker.isEnabled },
                      "pickers should re-enable when sound is on")
    }

    // The haptic-intensity picker only matters while the haptic is on.
    func testHapticIntensityGatedByHapticToggle() {
        step("Sound — intensity picker gated on the haptic toggle")
        app.tab("Sound").click()
        let haptic = control("cueHapticSwitch")
        XCTAssertTrue(haptic.waitForExistence(timeout: 10), "haptic toggle should exist")
        let intensity = control("hapticIntensity")
        XCTAssertTrue(intensity.exists, "intensity control should exist")

        XCTAssertEqual(haptic.value as? Int, 1, "haptic should default on")
        XCTAssertTrue(intensity.isEnabled, "intensity should be enabled while haptic is on")

        haptic.click()   // haptic off
        XCTAssertTrue(waitUntil(timeout: 3) { !intensity.isEnabled },
                      "intensity should disable when the haptic is off")
        haptic.click()   // restore
        XCTAssertTrue(waitUntil(timeout: 3) { intensity.isEnabled })
    }

    func testShortcutTabHasRecorderAndReset() {
        step("Open the Shortcut tab — expect Record + Reset buttons")
        app.tab("Shortcut").click()
        // Match by stable accessibility identifiers (titles contain glyphs that
        // mangle the AX label).
        XCTAssertTrue(app.buttons["recordShortcut"].waitForExistence(timeout: 5), "Record button should exist")
        XCTAssertTrue(app.buttons["resetShortcut"].waitForExistence(timeout: 5), "Reset button should exist")
    }

    func testShortcutTabOffersTriggerPresets() {
        step("Shortcut tab — expect the preset radios + custom-record button")
        app.tab("Shortcut").click()
        XCTAssertTrue(app.radioButtons["triggerDoubleShift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["triggerOptionTwo"].exists)
        XCTAssertTrue(app.buttons["recordShortcut"].exists)
    }

    // Selecting a preset must actually change the active trigger (shown in the
    // currentShortcut label), not just the radio state.
    func testPresetRadiosSwitchTheActiveTrigger() {
        step("Shortcut tab — pick ⌥2 preset, then back to ⇧⇧")
        app.tab("Shortcut").click()
        let current = app.staticTexts["currentShortcut"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))

        app.radioButtons["triggerOptionTwo"].click()
        XCTAssertTrue(waitUntil(timeout: 4) { (current.value as? String) == "⌥2" },
                      "⌥2 preset should become the active trigger")

        app.radioButtons["triggerDoubleShift"].click()
        XCTAssertTrue(waitUntil(timeout: 4) { (current.value as? String) == "⇧⇧" },
                      "⇧⇧ preset should become the active trigger again")
    }

    // QA H4: the window title follows the selected tab.
    func testWindowTitleFollowsSelectedTab() {
        step("Switch tabs — expect the window title to follow")
        XCTAssertTrue(app.tab("General").waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["General"].exists, "window should be titled after the first tab")
        app.tab("Apps").click()
        XCTAssertTrue(app.windows["Apps"].waitForExistence(timeout: 3))
        app.tab("Shortcut").click()
        XCTAssertTrue(app.windows["Shortcut"].waitForExistence(timeout: 3))
    }

    func testAppsTabListsPerAppRules() {
        step("Open the Apps tab — expect the per-app list")
        app.tab("Apps").click()
        XCTAssertTrue(app.staticTexts["Preferred Input per App"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Add app by name…"].exists)
    }

    func testToggleAutoUpdatePersistsVisually() {
        step("Toggle the 'auto-update' switch — expect it to flip")
        let toggle = control("autoUpdateSwitch")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let before = toggle.value as? Int
        toggle.click()
        let after = toggle.value as? Int
        XCTAssertNotEqual(before, after, "toggling should flip the switch state")
        toggle.click()   // restore
    }

    func testCmdWClosesTheWindow() {
        step("Press ⌘W — expect the Settings window to close")
        let general = app.tab("General")
        XCTAssertTrue(general.waitForExistence(timeout: 10))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(general.waitForExistence(timeout: 3), "⌘W should close the Settings window")
    }
}
