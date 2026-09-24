import AppKit
import Carbon
import CoreGraphics
import XCTest

// Runs only inside the disposable VM. The forced 120 ms edit pause ensures
// physical keys arrive WHILE FlicKey owns the caret; assertions inspect the
// actual destination text, not merely the chosen input source.
final class ContinuousAutoFixUITests: XCTestCase {
    private var flickey: XCUIApplication!
    private let abc = "com.apple.keylayout.ABC"
    private let hebrew = "com.apple.keylayout.Hebrew-PC"
    private let phrase = "akuo akuo guko tbh fu,c akuo "
    private let expected = "שלום שלום עולם אני כותב שלום "

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard FileManager.default.fileExists(atPath: "/Users/admin/.flickey-test-vm") else {
            throw XCTSkip("Physical-key tests run only in the isolated VM")
        }
        guard let pair = twoEnabledLayouts(), pair.latin == abc, pair.other == hebrew else {
            throw XCTSkip("Needs ABC and Hebrew-PC")
        }
        forceLatinInputSource()
        flickey = XCUIApplication()
        flickey.launchArguments = ["-uiTestReset", "-uiTestEnableAutoSwitch", "-uiTestSlowAutoFix"]
        flickey.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    override func tearDownWithError() throws {
        forceLatinInputSource()
        flickey?.terminate()
    }

    func testFastTypingIntoTextEditKeepsEveryCharacter() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        app.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                               "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        app.launch()
        defer { app.terminate() }
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
            field = app.textViews.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        postKey(0, flags: .maskCommand)
        postKey(51)
        XCTAssertTrue(waitUntil(timeout: 2) { (field.value as? String) == "" })
        forceLatinInputSource()

        step("TextEdit: type continuously across a held mid-sentence correction")
        let switchedMidSentence = typePhysical(phrase, interval: 20_000)
        XCTAssertTrue(waitUntil(timeout: 6) { (field.value as? String) == self.expected },
                      "actual TextEdit text: \(field.value ?? "nil")")
        XCTAssertEqual(currentInputSourceID(), hebrew)
        XCTAssertTrue(switchedMidSentence, "TextEdit must switch layouts before the sentence ends")
    }

    func testFastTypingIntoTerminalKeepsEveryCharacter() throws {
        try terminalFixture(expectMidSentenceSwitch: true)
    }

    func testVeryFastTypingIntoTerminalKeepsEveryCharacter() throws {
        try terminalFixture(expectMidSentenceSwitch: false, interval: 5_000)
    }

    func testVeryFastTypingIntoTextEditKeepsEveryCharacter() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        app.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                               "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        app.launch()
        defer { app.terminate() }
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
            field = app.textViews.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        postKey(0, flags: .maskCommand)
        postKey(51)
        XCTAssertTrue(waitUntil(timeout: 2) { (field.value as? String) == "" })
        forceLatinInputSource()

        step("TextEdit: 5 ms/key stress burst must preserve the entire sentence")
        _ = typePhysical(phrase, interval: 5_000)
        XCTAssertTrue(waitUntil(timeout: 6) { (field.value as? String) == self.expected },
                      "actual TextEdit text: \(field.value ?? "nil")")
        XCTAssertEqual(currentInputSourceID(), hebrew)
    }

    func testHebrewToEnglishCorrectionPreservesFollowingPhysicalKeys() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        app.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                               "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        app.launch()
        defer { app.terminate() }
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
            field = app.textViews.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        postKey(0, flags: .maskCommand)
        postKey(51)
        XCTAssertTrue(waitUntil(timeout: 2) { (field.value as? String) == "" })
        selectInputSource(id: hebrew)
        XCTAssertTrue(waitForSource(hebrew, 3))

        step("Hebrew-PC keys for hello hello hello must correct to English")
        _ = typePhysical("hello hello hello ", interval: 20_000)
        XCTAssertTrue(waitUntil(timeout: 6) { (field.value as? String) == "hello hello hello " },
                      "actual TextEdit text: \(field.value ?? "nil")")
        XCTAssertTrue([abc, "com.apple.keylayout.US"].contains(currentInputSourceID()),
                      "the target must be an enabled English layout, got \(currentInputSourceID())")
    }

    func testValidEnglishDoesNotAutoCorrect() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        app.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                               "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        app.launch()
        defer { app.terminate() }
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
            field = app.textViews.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        postKey(0, flags: .maskCommand)
        postKey(51)
        XCTAssertTrue(waitUntil(timeout: 2) { (field.value as? String) == "" })
        forceLatinInputSource()

        step("Valid English must stay exactly as typed, without switching layouts")
        _ = typePhysical("hello there ", interval: 20_000)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(field.value as? String, "hello there ")
        XCTAssertEqual(currentInputSourceID(), abc)
    }

    func testSafariPasswordFieldIsNeverRewritten() throws {
        try passwordFieldFixture("com.apple.Safari")
    }

    func testFirefoxPasswordFieldIsNeverRewritten() throws {
        try passwordFieldFixture("org.mozilla.firefox")
    }

    private func passwordFieldFixture(_ bundleID: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flickey-password-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("password.html")
        try """
        <html><head><meta charset="utf-8"><title>FlicKey password QA</title></head><body>
        <input id="draft" type="password" aria-label="QA password" autocomplete="off"
               autocorrect="off" autocapitalize="off" spellcheck="false">
        <textarea id="snapshot" aria-label="QA DOM snapshot" readonly></textarea>
        <script>
        const draft = document.getElementById('draft');
        draft.addEventListener('input', () => {
          document.getElementById('snapshot').value = draft.value;
        });
        </script></body></html>
        """.write(to: page, atomically: true, encoding: .utf8)
        let browser = XCUIApplication(bundleIdentifier: bundleID)
        browser.launchArguments = bundleID == "org.mozilla.firefox"
            ? ["-no-remote", "-profile", directory.path]
            : ["-ApplePersistenceIgnoreState", "YES"]
        if bundleID == "org.mozilla.firefox" {
            try """
            user_pref("app.update.auto", false);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.startup.homepage_override.mstone", "ignore");
            user_pref("browser.startup.page", 0);
            user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
            """.write(to: directory.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)
        }
        browser.launch()
        defer { browser.terminate() }
        browser.typeKey("l", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(page.absoluteString, forType: .string)
        browser.typeKey("v", modifierFlags: .command)
        browser.typeText("\n")
        if bundleID == "com.apple.Safari" {
            let button = browser.sheets.buttons["Open"]
            if button.waitForExistence(timeout: 2) { button.click() }
        }
        let field = browser.secureTextFields["QA password"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "local password fixture did not load")
        field.click()
        forceLatinInputSource()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        step("\(bundleID): never rewrite or switch source in a password field")
        _ = typePhysical("akuo akuo ", interval: 20_000)
        let snapshot = browser.textViews["QA DOM snapshot"]
        XCTAssertTrue(waitUntil(timeout: 3) { (snapshot.value as? String) == "akuo akuo " },
                      "actual password fixture DOM: \(snapshot.value ?? "nil")")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(snapshot.value as? String, "akuo akuo ")
        XCTAssertEqual(currentInputSourceID(), abc)
    }

    func testTerminalStillCorrectsWithoutInputBarrier() throws {
        flickey.terminate()
        flickey.launchArguments.append("-uiTestDisableInputBarrier")
        flickey.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try terminalFixture(expectMidSentenceSwitch: false)
    }

    private func terminalFixture(expectMidSentenceSwitch: Bool,
                                 interval: useconds_t = 20_000) throws {
        let terminal = XCUIApplication(bundleIdentifier: "com.apple.Terminal")
        terminal.launch()
        defer { terminal.terminate() }
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("flickey-continuous-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let ready = fixture.appendingPathComponent("ready")
        let result = fixture.appendingPathComponent("result")
        let script = fixture.appendingPathComponent("capture.command")
        let body = """
        #!/bin/zsh -f
        export LC_ALL=en_US.UTF-8
        bindkey -e
        unsetopt BEEP
        captured=''
        print -rn -- ready > '\(ready.path)'
        vared -p 'FlicKey QA> ' captured
        print -rn -- "$captured" > '\(result.path)'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        terminal.activate()
        forceLatinInputSource()
        terminal.typeText("/bin/zsh -f '\(script.path)'\n")
        XCTAssertTrue(waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: ready.path) })
        terminal.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        step("Terminal: type continuously through the AX-unavailable keyboard fallback")
        let switchedMidSentence = typePhysical(phrase, interval: interval)
        XCTAssertTrue(waitForSource(hebrew, 5), "Terminal should switch before the sentence ends")
        postKey(36) // submits vared's buffer; never executes typed text
        XCTAssertTrue(waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: result.path) })
        XCTAssertEqual(try String(contentsOf: result, encoding: .utf8), expected)
        if expectMidSentenceSwitch {
            XCTAssertTrue(switchedMidSentence, "Terminal must switch layouts before the sentence ends")
        }
    }

    func testSafariTextareaPreservesContinuousTyping() throws {
        try browserFixture("com.apple.Safari", contentEditable: false)
    }

    func testSafariContentEditablePreservesContinuousTyping() throws {
        try browserFixture("com.apple.Safari", contentEditable: true)
    }

    func testFirefoxTextareaPreservesContinuousTyping() throws {
        try browserFixture("org.mozilla.firefox", contentEditable: false)
    }

    func testFirefoxContentEditablePreservesContinuousTyping() throws {
        try browserFixture("org.mozilla.firefox", contentEditable: true)
    }

    func testSafariTwoTabsKeepIndependentCorrections() throws {
        try browserTabFixture("com.apple.Safari")
    }

    func testFirefoxTwoTabsKeepIndependentCorrections() throws {
        try browserTabFixture("org.mozilla.firefox")
    }

    // A tab change must not make the rewrite address the wrong document. Both
    // tabs receive real-key bursts and are inspected again after leaving them.
    private func browserTabFixture(_ bundleID: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flickey-tab-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func page(_ label: String, editable: Bool) throws -> URL {
            let editor = editable
                ? "<div id='draft' contenteditable='true' aria-label='QA draft \(label)' style='width:600px;height:200px;border:1px solid black' spellcheck='false'></div>"
                : "<textarea id='draft' aria-label='QA draft \(label)' rows='12' cols='60' autocomplete='off' autocorrect='off' autocapitalize='off' spellcheck='false'></textarea>"
            let html = """
            <html><head><meta charset="utf-8"><title>FlicKey tab \(label)</title></head><body>
            \(editor)
            <textarea id="snapshot" aria-label="QA DOM snapshot \(label)" readonly></textarea>
            <script>
            const draft = document.getElementById('draft');
            draft.addEventListener('input', () => {
              document.getElementById('snapshot').value = draft.isContentEditable ? draft.textContent : draft.value;
            });
            </script></body></html>
            """
            let url = directory.appendingPathComponent("\(label).html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let first = try page("first", editable: false)
        let second = try page("second", editable: true)
        let browser = XCUIApplication(bundleIdentifier: bundleID)
        browser.launchArguments = bundleID == "org.mozilla.firefox"
            ? ["-no-remote", "-profile", directory.path]
            : ["-ApplePersistenceIgnoreState", "YES"]
        if bundleID == "org.mozilla.firefox" {
            try """
            user_pref("app.update.auto", false);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.startup.homepage_override.mstone", "ignore");
            user_pref("browser.startup.page", 0);
            user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
            """.write(to: directory.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)
        }
        browser.launch()
        defer { browser.terminate() }

        func open(_ url: URL, label: String) {
            browser.activate()
            // Character-based XCUI shortcuts can resolve against the active
            // Hebrew source after the preceding tab auto-corrects.
            if currentInputSourceID() == abc {
                browser.typeKey("l", modifierFlags: .command)
            } else {
                postPhysicalShortcut(keyCode: 37, flags: .maskCommand) // ⌘L
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            if currentInputSourceID() == abc {
                browser.typeKey("v", modifierFlags: .command)
            } else {
                postPhysicalShortcut(keyCode: 9, flags: .maskCommand) // ⌘V
            }
            browser.typeText("\n")
            if bundleID == "com.apple.Safari" {
                let button = browser.sheets.buttons["Open"]
                if button.waitForExistence(timeout: 2) { button.click() }
            }
            XCTAssertTrue(browser.textViews["QA draft \(label)"].waitForExistence(timeout: 8),
                          "\(label) tab failed to load")
        }
        func assertText(_ label: String) {
            let snapshot = browser.textViews["QA DOM snapshot \(label)"]
            XCTAssertTrue(waitUntil(timeout: 6) {
                (snapshot.value as? String)?.replacingOccurrences(of: "\u{00A0}", with: " ") == self.expected
            }, "\(label) actual DOM text: \(snapshot.value ?? "nil")")
        }

        step("\(bundleID): correct first tab's textarea")
        open(first, label: "first")
        browser.textViews["QA draft first"].click()
        forceLatinInputSource()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(typePhysical(phrase, interval: 20_000), "first tab must switch mid-sentence")
        assertText("first")

        step("\(bundleID): open second tab and correct its independent contenteditable")
        postPhysicalShortcut(keyCode: 17, flags: .maskCommand) // ⌘T
        open(second, label: "second")
        browser.textViews["QA draft second"].click()
        forceLatinInputSource()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(typePhysical(phrase, interval: 20_000), "second tab must switch mid-sentence")
        assertText("second")

        step("\(bundleID): return to first tab, then second; neither text may be corrupted")
        postPhysicalShortcut(keyCode: 48, flags: [.maskControl, .maskShift]) // previous tab
        XCTAssertTrue(browser.textViews["QA draft first"].waitForExistence(timeout: 5))
        assertText("first")
        postPhysicalShortcut(keyCode: 48, flags: .maskControl) // next tab
        XCTAssertTrue(browser.textViews["QA draft second"].waitForExistence(timeout: 5))
        assertText("second")
    }

    func testRussianAsThirdEnabledLayoutTargetsRussianNotHebrew() throws {
        let russian = "com.apple.keylayout.Russian"
        guard let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first(where: {
                  guard let pointer = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
                  return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String == russian
              }) else {
            XCTFail("Russian layout absent from provisioned VM")
            return
        }
        XCTAssertEqual(TISEnableInputSource(source), noErr)
        defer { _ = TISDisableInputSource(source); forceLatinInputSource() }
        flickey.terminate()
        flickey.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let app = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        app.launchArguments = ["-NSAutomaticCapitalizationEnabled", "NO",
                               "-NSAutomaticSpellingCorrectionEnabled", "NO"]
        app.launch()
        defer { app.terminate() }
        var field = app.textViews.firstMatch
        if !field.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
            field = app.textViews.firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        postKey(0, flags: .maskCommand)
        postKey(51)
        XCTAssertTrue(waitUntil(timeout: 2) { (field.value as? String) == "" })
        forceLatinInputSource()

        step("Three enabled layouts: ABC keys ghbdtn must become Russian привет")
        let raw = "ghbdtn ghbdtn ghbdtn "
        _ = typePhysical(raw, interval: 20_000)
        XCTAssertTrue(waitUntil(timeout: 6) { (field.value as? String) == "привет привет привет " },
                      "actual TextEdit text: \(field.value ?? "nil")")
        XCTAssertEqual(currentInputSourceID(), russian)
    }

    private func browserFixture(_ bundleID: String, contentEditable: Bool) throws {
        let editor = contentEditable
            ? "<div id='draft' contenteditable='true' aria-label='QA draft' style='width:600px;height:200px;border:1px solid black' spellcheck='false'></div>"
            : "<textarea id='draft' aria-label='QA draft' rows='12' cols='60' autocomplete='off' autocorrect='off' autocapitalize='off' spellcheck='false'></textarea>"
        let html = """
        <html><head><meta charset="utf-8"><title>FlicKey typing QA</title></head><body>
        \(editor)
        <textarea id="snapshot" aria-label="QA DOM snapshot" readonly></textarea>
        <script>
        const draft = document.getElementById('draft');
        draft.addEventListener('input', () => {
          document.getElementById('snapshot').value = draft.isContentEditable ? draft.textContent : draft.value;
        });
        </script></body></html>
        """
        let page = FileManager.default.temporaryDirectory
            .appendingPathComponent("flickey-web-\(UUID().uuidString).html")
        try html.write(to: page, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: page) }
        let browser = XCUIApplication(bundleIdentifier: bundleID)
        browser.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        var profile: URL?
        if bundleID == "org.mozilla.firefox" {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("flickey-firefox-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try """
            user_pref("app.update.auto", false);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.startup.homepage_override.mstone", "ignore");
            user_pref("browser.startup.page", 0);
            user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
            """.write(to: directory.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)
            profile = directory
            browser.launchArguments = ["-no-remote", "-profile", directory.path]
        }
        browser.launch()
        defer {
            browser.terminate()
            if let profile { try? FileManager.default.removeItem(at: profile) }
        }
        browser.typeKey("l", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(page.absoluteString, forType: .string)
        browser.typeKey("v", modifierFlags: .command)
        browser.typeText("\n")
        if bundleID == "com.apple.Safari" {
            let open = browser.sheets.buttons["Open"]
            if open.waitForExistence(timeout: 2) { open.click() }
        }
        let field = browser.textViews["QA draft"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Local web editor did not load")
        field.click()
        forceLatinInputSource()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        step("\(bundleID) \(contentEditable ? "contenteditable" : "textarea"): continuous real-key typing")
        let snapshot = browser.textViews["QA DOM snapshot"]
        let switchedMidSentence = typePhysical(phrase, interval: 20_000)
        XCTAssertTrue(waitUntil(timeout: 6) {
            (snapshot.value as? String)?.replacingOccurrences(of: "\u{00A0}", with: " ") == self.expected
        }, "actual DOM text: \(snapshot.value ?? "nil")")
        XCTAssertEqual(currentInputSourceID(), hebrew)
        XCTAssertTrue(switchedMidSentence, "Web editor must switch layouts before the sentence ends")
    }

    @discardableResult
    private func typePhysical(_ text: String, interval: useconds_t) -> Bool {
        let codes: [Character: CGKeyCode] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
            "h": 4, "k": 40, "l": 37, "n": 45, "o": 31, "r": 15, "t": 17,
            "u": 32, "v": 9, ",": 43, " ": 49,
        ]
        var midSentenceSwitch = false
        for (index, character) in text.enumerated() {
            guard let code = codes[character] else { XCTFail("Unmapped physical key"); return false }
            postKey(code)
            RunLoop.current.run(until: Date().addingTimeInterval(Double(interval) / 1_000_000))
            // The Debug fixture holds the edit for 120 ms, and AX's Terminal
            // probe can add ~130 ms. Check before the final word, not during
            // that deliberately extended transaction.
            if index == 23 { midSentenceSwitch = currentInputSourceID() == hebrew }
        }
        return midSentenceSwitch
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
