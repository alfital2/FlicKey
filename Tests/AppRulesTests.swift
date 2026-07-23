import XCTest

final class AppRulesTests: XCTestCase {

    private let keys = ["appInputOverrides", "customApps", "hiddenBuiltins"]
    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    func testEditableIsSortedAlphabetically() {
        let names = AppRules.editable.map { $0.name }
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }

    func testKnownBuiltinHasRule() {
        XCTAssertNotNil(AppRules.rule(forNormalizedName: "terminal"))
    }

    func testUnknownAppHasNoRule() {
        XCTAssertNil(AppRules.rule(forNormalizedName: "some-random-app-that-does-not-exist"))
    }

    func testAddCustomThenRemove() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "ZZTestApp", bundleID: "com.test.zz")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "zztestapp" }) else {
            return XCTFail("custom app not added")
        }
        AppRules.remove(app)
        XCTAssertFalse(AppRules.all.contains { $0.matchKey == "zztestapp" })
    }

    func testAddingDuplicateOfBuiltinFails() {
        XCTAssertFalse(AppRules.addCustom(CustomApp(name: "Terminal", bundleID: "com.apple.Terminal")))
    }

    func testSetRuleOverrideIsHonored() {
        guard let app = AppRules.all.first(where: { $0.matchKey == "terminal" }) else {
            return XCTFail("Terminal missing")
        }
        AppRules.setRule(.source("com.apple.keylayout.TestLayout"), for: app)
        XCTAssertEqual(AppRules.rule(forNormalizedName: "terminal"),
                       .source("com.apple.keylayout.TestLayout"))
    }

    func testCustomAppResolvesToASource() {
        AppRules.addCustom(CustomApp(name: "ZZApp", bundleID: "com.test.zz"))
        let app = AppRules.all.first { $0.matchKey == "zzapp" }
        XCTAssertNotNil(app?.rule.sourceID, "custom app should resolve to a concrete source")
    }

    func testReAddingRemovedBuiltinRestoresIt() {
        guard let terminal = AppRules.all.first(where: { $0.matchKey == "terminal" }) else {
            return XCTFail("Terminal missing")
        }
        AppRules.remove(terminal) // hides the built-in
        XCTAssertFalse(AppRules.all.contains { $0.matchKey == "terminal" })

        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "Terminal", bundleID: "com.apple.Terminal")))
        XCTAssertTrue(AppRules.all.contains { $0.matchKey == "terminal" })
    }

    // A conversation-provider app (Teams) is identified by BUNDLE ID, not name.
    // Adding it as a custom entry — under any name/variant — must be refused, so
    // it can't create a duplicate row nor a forced .normal row that shadows the
    // provider and silently disables per-conversation memory.
    func testAddingConversationProviderAppIsRejected() {
        XCTAssertFalse(AppRules.addCustom(CustomApp(name: "Microsoft Teams (work or school)",
                                                    bundleID: "com.microsoft.teams2")),
                       "a conversation-provider app must not be addable as a custom entry")
        XCTAssertFalse(AppRules.all.contains { $0.bundleID == "com.microsoft.teams2" && $0.isCustom })
    }

    // A legacy/stray custom entry for a conversation-provider app (e.g. one added
    // before per-conversation support existed) must NOT shadow the provider:
    // Teams must never surface as a forced .normal row, which would route to
    // .force and kill per-chat memory.
    func testCustomEntryDoesNotShadowConversationProvider() {
        RulesStore.addCustomApp(CustomApp(name: "Microsoft Teams", bundleID: "com.microsoft.teams2"))
        let teamsRows = AppRules.all.filter {
            $0.bundleID == "com.microsoft.teams2" || $0.matchKey == "microsoft teams"
        }
        XCTAssertFalse(teamsRows.contains { $0.isCustom },
                       "a custom entry must not shadow the conversation provider")
        XCTAssertFalse(teamsRows.contains { $0.kind == .normal },
                       "Teams must never appear as a forced normal row")
    }

    // Removing a conversation-provider app (e.g. Teams) must actually take it out
    // of the list — the conversation loop must honor hiddenBuiltins, or Remove
    // silently does nothing (the app reappears every rebuild of `all`).
    func testRemovingConversationAppHidesIt() throws {
        guard let teams = AppRules.all.first(where: { $0.isConversationApp }) else {
            throw XCTSkip("no conversation-provider app installed on this machine")
        }
        AppRules.remove(teams)
        XCTAssertFalse(AppRules.all.contains { $0.matchKey == teams.matchKey },
                       "a removed conversation app must not reappear")
    }

    // ...and re-adding it (by its provider bundle ID) brings it back rather than
    // being silently refused as a duplicate.
    func testReAddingRemovedConversationAppRestoresIt() throws {
        guard let teams = AppRules.all.first(where: { $0.isConversationApp }) else {
            throw XCTSkip("no conversation-provider app installed on this machine")
        }
        AppRules.remove(teams)
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: teams.name, bundleID: teams.bundleID)),
                      "re-adding a removed conversation app should restore it")
        XCTAssertTrue(AppRules.all.contains { $0.matchKey == teams.matchKey && $0.isConversationApp })
    }

    func testBrowsersDefaultToAuto() {
        // Whatever browsers are installed should default to AUTO.
        let browsers = AppRules.all.filter { $0.isBrowser }
        for browser in browsers where RulesStore.overrides()[browser.matchKey] == nil {
            XCTAssertTrue(browser.rule.isAuto, "\(browser.name) should default to AUTO")
        }
    }

    func testInstalledConversationAppDefaultsToPerConversationAuto() throws {
        // On the dev machine Teams is installed; it should be listed as a
        // conversation app defaulting to AUTO (per-conversation), NOT a forced
        // source like "ABC".
        guard let teams = AppRules.all.first(where: { $0.matchKey == "microsoft teams" }) else {
            throw XCTSkip("Microsoft Teams not installed on this machine")
        }
        XCTAssertTrue(teams.isConversationApp)
        XCTAssertFalse(teams.isBrowser)
        XCTAssertEqual(teams.rule, .auto, "conversation app must default to AUTO, not a forced source")
    }
}
