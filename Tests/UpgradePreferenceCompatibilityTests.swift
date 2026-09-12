import XCTest

// Upgrade contract: preferences written by released builds must survive the
// move away from the old hardcoded ordinary-app catalog. This deliberately
// seeds the raw UserDefaults representation used by those builds, then lets the
// current AppRules migration run.
final class UpgradePreferenceCompatibilityTests: XCTestCase {
    private let keys = [
        "appInputOverrides",
        "customApps",
        "hiddenBuiltins",
        "importAllApps",
        "rememberVisitedApps",
        "appLastUsedInputSources",
        "siteInputMemory",
        "conversationInputMemory",
    ]

    override func setUp() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        BrowserCatalog.setApplicationURLsProviderForTesting { [] }
        AppRules.resetInstalledAppsProviderForTesting()
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        BrowserCatalog.resetApplicationURLsProviderForTesting()
        AppRules.resetInstalledAppsProviderForTesting()
    }

    func testUpgradePreservesExplicitAppSiteAndConversationPreferences() throws {
        let overrides = [
            "terminal": "com.apple.keylayout.ABC",
            "my editor": "com.apple.keylayout.Swedish-Pro",
            "safari": "__auto__",
        ]
        let legacyCustomApps = [
            CustomApp(name: "My Editor", bundleID: "com.example.editor"),
        ]
        let hiddenBuiltins = ["pages"]
        let siteMemory = [
            "example.com": "com.apple.keylayout.Hebrew-PC",
            "developer.apple.com": "com.apple.keylayout.ABC",
        ]
        let conversationMemory = [
            "teams": [
                "project alpha": "com.apple.keylayout.Swedish-Pro",
                "family": "com.apple.keylayout.Hebrew-PC",
            ],
        ]

        UserDefaults.standard.set(overrides, forKey: "appInputOverrides")
        UserDefaults.standard.set(try JSONEncoder().encode(legacyCustomApps),
                                  forKey: "customApps")
        UserDefaults.standard.set(hiddenBuiltins, forKey: "hiddenBuiltins")
        UserDefaults.standard.set(siteMemory, forKey: "siteInputMemory")
        UserDefaults.standard.set(conversationMemory, forKey: "conversationInputMemory")

        // Terminal used to be a hardcoded ordinary app. The current version
        // discovers its installed identity and keeps the user's explicit rule.
        AppRules.setInstalledAppsProviderForTesting {
            [CustomApp(name: "Terminal", bundleID: "com.apple.Terminal")]
        }
        _ = AppRules.all

        XCTAssertEqual(AppRules.rule(forBundleID: "com.apple.Terminal",
                                     normalizedName: "terminal"),
                       .source("com.apple.keylayout.ABC"))
        XCTAssertEqual(AppRules.rule(forBundleID: "com.example.editor",
                                     normalizedName: "my editor"),
                       .source("com.apple.keylayout.Swedish-Pro"))

        // Migration may add Terminal's bundle identity, but must not delete or
        // rewrite any explicit rule or an existing custom app.
        XCTAssertEqual(RulesStore.overrides(), overrides)
        let migratedApps = RulesStore.customApps()
        XCTAssertTrue(migratedApps.contains {
            $0.name == "My Editor" && $0.bundleID == "com.example.editor"
        })
        XCTAssertTrue(migratedApps.contains {
            $0.name == "Terminal" && $0.bundleID == "com.apple.Terminal"
        })
        XCTAssertEqual(RulesStore.hiddenBuiltins(), Set(hiddenBuiltins))

        XCTAssertEqual(SiteMemoryStore.sourceID(for: "example.com"),
                       "com.apple.keylayout.Hebrew-PC")
        XCTAssertEqual(SiteMemoryStore.sourceID(for: "developer.apple.com"),
                       "com.apple.keylayout.ABC")
        XCTAssertEqual(ContextMemoryStore.sourceID(namespace: "teams", key: "project alpha"),
                       "com.apple.keylayout.Swedish-Pro")
        XCTAssertEqual(ContextMemoryStore.sourceID(namespace: "teams", key: "family"),
                       "com.apple.keylayout.Hebrew-PC")
    }
}
