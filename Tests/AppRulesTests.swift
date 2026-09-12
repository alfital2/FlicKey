import XCTest

final class AppRulesTests: XCTestCase {

    private let keys = ["appInputOverrides", "customApps", "hiddenBuiltins", "importAllApps",
                        "rememberVisitedApps", "appLastUsedInputSources"]
    override func setUp() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        BrowserCatalog.resetApplicationURLsProviderForTesting()
        AppRules.resetInstalledAppsProviderForTesting()
    }
    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        BrowserCatalog.resetApplicationURLsProviderForTesting()
        AppRules.resetInstalledAppsProviderForTesting()
    }

    func testEditableIsSortedAlphabetically() {
        let names = AppRules.editable.map { $0.name }
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }

    func testOrdinaryAppsAreNotHardcoded() {
        XCTAssertNil(AppRules.rule(forNormalizedName: "terminal"))
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

    func testAddingDuplicateCustomAppFails() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "Terminal", bundleID: "com.apple.Terminal")))
        XCTAssertFalse(AppRules.addCustom(CustomApp(name: "Terminal", bundleID: "com.apple.Terminal")))
    }

    func testSetRuleOverrideIsHonored() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "Terminal", bundleID: "com.apple.Terminal")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "terminal" }) else {
            return XCTFail("Terminal missing")
        }
        AppRules.setRule(.source("com.apple.keylayout.TestLayout"), for: app)
        XCTAssertEqual(AppRules.rule(forNormalizedName: "terminal"),
                       .source("com.apple.keylayout.TestLayout"))
    }

    func testCustomAppDefaultsToUndefined() {
        AppRules.addCustom(CustomApp(name: "ZZApp", bundleID: "com.test.zz"))
        let app = AppRules.all.first { $0.matchKey == "zzapp" }
        XCTAssertEqual(app?.rule, .undefined)
    }

    func testImportAllListsOrdinaryAppsAsUndefined() {
        AppRules.setInstalledAppsProviderForTesting {
            [CustomApp(name: "Example Editor", bundleID: "com.test.editor")]
        }
        AppRules.setImportsAllApps(true)

        let app = AppRules.all.first { $0.bundleID == "com.test.editor" }
        XCTAssertEqual(app?.rule, .undefined)
        XCTAssertTrue(app?.isImported == true)
        XCTAssertEqual(AppRules.rule(forBundleID: "com.test.editor", normalizedName: "renamed"),
                       .undefined)
    }

    func testImportedUndefinedAppDisappearsWhenImportIsTurnedOff() {
        AppRules.setInstalledAppsProviderForTesting {
            [CustomApp(name: "Example Editor", bundleID: "com.test.editor")]
        }
        AppRules.setImportsAllApps(true)
        XCTAssertNotNil(AppRules.all.first { $0.bundleID == "com.test.editor" })

        AppRules.setImportsAllApps(false)
        XCTAssertNil(AppRules.all.first { $0.bundleID == "com.test.editor" })
    }

    func testChoosingSourcePersistsImportedAppAndEnforcesAfterImportIsOff() {
        AppRules.setInstalledAppsProviderForTesting {
            [CustomApp(name: "Example Editor", bundleID: "com.test.editor")]
        }
        AppRules.setImportsAllApps(true)
        guard let imported = AppRules.all.first(where: { $0.bundleID == "com.test.editor" }) else {
            return XCTFail("imported app missing")
        }

        AppRules.setRule(.source("test.layout"), for: imported)
        AppRules.setImportsAllApps(false)

        XCTAssertTrue(RulesStore.customApps().contains { $0.bundleID == "com.test.editor" })
        XCTAssertEqual(AppRules.rule(forBundleID: "com.test.editor", normalizedName: "renamed"),
                       .source("test.layout"))
    }

    func testChangingSourceLearnsAndPersistsImportedOrdinaryApp() {
        AppRules.setInstalledAppsProviderForTesting {
            [CustomApp(name: "Example Editor", bundleID: "com.test.editor")]
        }
        AppRules.setImportsAllApps(true)
        guard let imported = AppRules.appRule(forBundleID: "com.test.editor",
                                              normalizedName: "renamed") else {
            return XCTFail("imported app missing")
        }

        XCTAssertTrue(imported.learnsAppPreference)
        XCTAssertEqual(imported.rule, .undefined)
        AppRules.rememberSource("test.first-layout", for: imported)

        XCTAssertTrue(RulesStore.customApps().contains { $0.bundleID == "com.test.editor" })
        XCTAssertEqual(AppRules.rule(forBundleID: "com.test.editor", normalizedName: "renamed"),
                       .auto)
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "com.test.editor"),
                       "test.first-layout")

        AppRules.setImportsAllApps(false)
        guard let persisted = AppRules.appRule(forBundleID: "com.test.editor",
                                               normalizedName: "renamed") else {
            return XCTFail("learned app did not persist")
        }
        AppRules.rememberSource("test.second-layout", for: persisted)
        XCTAssertEqual(AppRules.rule(forBundleID: "com.test.editor", normalizedName: "renamed"),
                       .auto)
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "com.test.editor"),
                       "test.second-layout")
    }

    func testFixedRuleIsNeverOverwrittenByObservedInputChanges() {
        AppRules.addCustom(CustomApp(name: "Fixed App", bundleID: "com.test.fixed"))
        guard let app = AppRules.appRule(forBundleID: "com.test.fixed",
                                         normalizedName: "fixed app") else {
            return XCTFail("fixed app missing")
        }
        AppRules.setRule(.source("test.fixed-layout"), for: app)
        guard let fixed = AppRules.appRule(forBundleID: "com.test.fixed",
                                           normalizedName: "fixed app") else {
            return XCTFail("fixed rule missing")
        }

        AppRules.rememberSource("test.manual-layout", for: fixed)

        XCTAssertEqual(AppRules.rule(forBundleID: "com.test.fixed",
                                     normalizedName: "fixed app"),
                       .source("test.fixed-layout"))
        XCTAssertNil(AppLastUsedInputStore.sourceID(for: "com.test.fixed"))
    }

    func testRemovingAppClearsItsPersistentLastUsedValue() {
        AppRules.addCustom(CustomApp(name: "Remembered App", bundleID: "com.test.remembered"))
        guard let app = AppRules.appRule(forBundleID: "com.test.remembered",
                                         normalizedName: "remembered app") else {
            return XCTFail("remembered app missing")
        }
        AppLastUsedInputStore.set("test.layout", for: app.memoryKey)

        AppRules.remove(app)

        XCTAssertNil(AppLastUsedInputStore.sourceID(for: "com.test.remembered"))
    }

    func testAppWideLearningNeverOverridesBrowserOrConversationMemory() {
        let browser = AppRule(name: "Browser", bundleID: "com.test.browser", rule: .auto,
                              isCustom: false, isImported: false, kind: .browser)
        let conversation = AppRule(name: "Chat", bundleID: "com.test.chat", rule: .auto,
                                   isCustom: false, isImported: false, kind: .conversation)

        AppRules.rememberSource("test.layout", for: browser)
        AppRules.rememberSource("test.layout", for: conversation)

        XCTAssertNil(RulesStore.overrides()[browser.matchKey])
        XCTAssertNil(RulesStore.overrides()[conversation.matchKey])
    }

    func testVisitDoesNotAddAnUnlistedAppWhenAutomaticRememberingIsOff() {
        let app = AppRules.appRuleForVisit(bundleID: "com.test.visited",
                                           name: "Visited App",
                                           sourceID: "test.layout")
        XCTAssertNil(app)
        XCTAssertTrue(RulesStore.customApps().isEmpty)
    }

    func testVisitAddsOrdinaryAppWithCurrentSourceWhenAutomaticRememberingIsOn() {
        AppRules.setRemembersVisitedApps(true)

        let app = AppRules.appRuleForVisit(bundleID: "com.test.visited",
                                           name: "Visited App",
                                           sourceID: "test.initial-layout")

        XCTAssertEqual(app?.rule, .auto)
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "com.test.visited"),
                       "test.initial-layout")
        XCTAssertTrue(app?.learnsAppPreference == true)
        XCTAssertTrue(RulesStore.customApps().contains { $0.bundleID == "com.test.visited" })
    }

    func testAutomaticVisitInitializesImportedUndefinedApp() {
        AppRules.setInstalledAppsProviderForTesting {
            [CustomApp(name: "Imported App", bundleID: "com.test.imported")]
        }
        AppRules.setImportsAllApps(true)
        AppRules.setRemembersVisitedApps(true)

        let app = AppRules.appRuleForVisit(bundleID: "com.test.imported",
                                           name: "Imported App",
                                           sourceID: "test.current-layout")

        XCTAssertEqual(app?.rule, .auto)
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "com.test.imported"),
                       "test.current-layout")
        XCTAssertTrue(RulesStore.customApps().contains { $0.bundleID == "com.test.imported" })
    }

    func testReturningToKnownAppKeepsSavedPreferenceInsteadOfCurrentSource() {
        AppRules.setRemembersVisitedApps(true)
        _ = AppRules.appRuleForVisit(bundleID: "com.test.visited",
                                     name: "Visited App",
                                     sourceID: "test.saved-layout")

        let returning = AppRules.appRuleForVisit(bundleID: "com.test.visited",
                                                 name: "Visited App",
                                                 sourceID: "test.other-current-layout")

        XCTAssertEqual(returning?.rule, .auto)
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "com.test.visited"),
                       "test.saved-layout")
    }

    func testAutomaticVisitNeverAddsConversationProviderAsOrdinaryApp() {
        AppRules.setRemembersVisitedApps(true)

        _ = AppRules.appRuleForVisit(bundleID: "com.microsoft.teams2",
                                     name: "Microsoft Teams",
                                     sourceID: "test.layout")

        XCTAssertFalse(RulesStore.customApps().contains { $0.bundleID == "com.microsoft.teams2" })
    }

    func testExistingExplicitRuleMigratesWithoutRestoringUntouchedDefaults() {
        AppRules.setInstalledAppsProviderForTesting {
            [
                CustomApp(name: "Configured App", bundleID: "com.test.configured"),
                CustomApp(name: "Untouched App", bundleID: "com.test.untouched"),
            ]
        }
        RulesStore.set("test.saved.layout", forMatchKey: "configured app")

        XCTAssertEqual(AppRules.rule(forBundleID: "com.test.configured",
                                     normalizedName: "configured app"),
                       .source("test.saved.layout"))
        XCTAssertTrue(RulesStore.customApps().contains {
            $0.bundleID == "com.test.configured"
        })
        XCTAssertNil(AppRules.rule(forBundleID: "com.test.untouched",
                                   normalizedName: "untouched app"))
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

    func testBrowsersDefaultToAuto() throws {
        // Whatever browsers are installed should default to AUTO.
        let browsers = AppRules.all.filter { $0.isBrowser }
        guard !browsers.isEmpty else { throw XCTSkip("no browser discovered") }
        for browser in browsers where RulesStore.overrides()[browser.matchKey] == nil {
            XCTAssertTrue(browser.rule.isAuto, "\(browser.name) should default to AUTO")
        }
    }

    func testDiscoveredSafariHonorsLegacyNameKeyedOverride() throws {
        guard BrowserCatalog.installed().contains(where: { $0.bundleID == "com.apple.Safari" }) else {
            throw XCTSkip("Safari was not discovered")
        }
        UserDefaults.standard.set(["safari": "test.layout.legacy"],
                                  forKey: "appInputOverrides")
        let safari = AppRules.all.first { $0.bundleID == "com.apple.Safari" }
        XCTAssertEqual(safari?.rule, .source("test.layout.legacy"))
    }

    func testHideAndReAddDiscoveredBrowser() throws {
        guard let browser = AppRules.all.first(where: \.isBrowser) else {
            throw XCTSkip("no browser discovered")
        }
        AppRules.remove(browser)
        XCTAssertFalse(AppRules.all.contains { $0.bundleID == browser.bundleID })
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: browser.name, bundleID: browser.bundleID)))
        XCTAssertTrue(AppRules.all.contains { $0.bundleID == browser.bundleID && $0.isBrowser })
    }

    func testLegacyCustomEntryDoesNotShadowDiscoveredBrowser() throws {
        guard let browser = AppRules.all.first(where: \.isBrowser) else {
            throw XCTSkip("no browser discovered")
        }
        RulesStore.addCustomApp(CustomApp(name: "Legacy \(browser.name)",
                                          bundleID: browser.bundleID))
        let rows = AppRules.all.filter { $0.bundleID == browser.bundleID }
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isBrowser)
        XCTAssertFalse(rows[0].isCustom)
    }

    func testAddingDiscoveredBrowserAsCustomIsRejected() throws {
        guard let browser = AppRules.all.first(where: \.isBrowser) else {
            throw XCTSkip("no browser discovered")
        }
        XCTAssertFalse(AppRules.addCustom(CustomApp(name: browser.name,
                                                    bundleID: browser.bundleID)))
    }

    func testBundleIDRoutingSurvivesRenamedBrowser() throws {
        guard let browser = AppRules.all.first(where: \.isBrowser) else {
            throw XCTSkip("no browser discovered")
        }
        RulesStore.set("test.layout.forced", forMatchKey: browser.matchKey)
        XCTAssertEqual(AppRules.rule(forBundleID: browser.bundleID,
                                     normalizedName: "renamed browser"),
                       .source("test.layout.forced"))
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
