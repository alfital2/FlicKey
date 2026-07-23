import XCTest

// Unit tests for the AppRules helpers FocusWatcher relies on: name normalization
// (used to resolve a running app to its rule) and forcedSourceID (which apps to
// observe + what to force), plus the appRulesChanged signal that re-syncs the
// observer set. Isolated by clearing the persisted rule keys around each test.
final class AppRulesMatchingTests: XCTestCase {

    private let keys = ["appInputOverrides", "customApps", "hiddenBuiltins"]
    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    // MARK: - normalizedName (pure)

    func testNormalizeLowercasesAndTrims() {
        XCTAssertEqual(AppRules.normalizedName("  Ghostty  "), "ghostty")
        XCTAssertEqual(AppRules.normalizedName("TERMINAL"), "terminal")
    }

    func testNormalizeNilAndEmpty() {
        XCTAssertEqual(AppRules.normalizedName(nil), "")
        XCTAssertEqual(AppRules.normalizedName(""), "")
        XCTAssertEqual(AppRules.normalizedName("   "), "")
    }

    // App names from the system can carry zero-width / bidi format characters
    // (we saw exactly this on "WhatsApp"); they must be stripped before matching.
    func testNormalizeStripsBidiAndZeroWidth() {
        XCTAssertEqual(AppRules.normalizedName("\u{200E}WhatsApp"), "whatsapp")   // LEFT-TO-RIGHT MARK
        XCTAssertEqual(AppRules.normalizedName("Ghostty\u{200B}"), "ghostty")     // ZERO WIDTH SPACE
        XCTAssertEqual(AppRules.normalizedName("\u{200F}Pages\u{200E}"), "pages") // RLM…LRM
    }

    // MARK: - forcedSourceID

    func testForcedSourceIDNilForUnlistedApp() {
        XCTAssertNil(AppRules.forcedSourceID(forAppNamed: "NoSuchAppXYZ"))
    }

    func testForcedSourceIDNilForEmptyName() {
        XCTAssertNil(AppRules.forcedSourceID(forAppNamed: nil))
        XCTAssertNil(AppRules.forcedSourceID(forAppNamed: ""))
    }

    func testForcedSourceIDReturnsOverride() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "ZZForce", bundleID: "com.test.zz")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "zzforce" }) else {
            return XCTFail("custom app not added")
        }
        AppRules.setRule(.source("com.test.LayoutX"), for: app)
        XCTAssertEqual(AppRules.forcedSourceID(forAppNamed: "ZZForce"), "com.test.LayoutX")
    }

    // Resolution must match the same normalization AppWatcher uses (case, spaces,
    // bidi) so the observed set and the forced layout agree.
    func testForcedSourceIDMatchesNormalized() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "ZZForce", bundleID: "com.test.zz")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "zzforce" }) else {
            return XCTFail("custom app not added")
        }
        AppRules.setRule(.source("com.test.LayoutX"), for: app)
        XCTAssertEqual(AppRules.forcedSourceID(forAppNamed: "  zzFORCE "), "com.test.LayoutX")
        XCTAssertEqual(AppRules.forcedSourceID(forAppNamed: "ZZForce\u{200B}"), "com.test.LayoutX")
    }

    // An app explicitly set to AUTO (browser-style per-site) is NOT a forced
    // source, so FocusWatcher must not observe/force it.
    func testForcedSourceIDNilForAutoRule() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "ZZAuto", bundleID: "com.test.auto")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "zzauto" }) else {
            return XCTFail("custom app not added")
        }
        AppRules.setRule(.auto, for: app)
        XCTAssertNil(AppRules.forcedSourceID(forAppNamed: "ZZAuto"))
    }

    // MARK: - appRulesChanged notification (FocusWatcher re-syncs on it)

    func testSetRulePostsAppRulesChanged() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "ZZNotify", bundleID: "com.test.n")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "zznotify" }) else {
            return XCTFail("custom app not added")
        }
        expectation(forNotification: .appRulesChanged, object: nil)
        AppRules.setRule(.source("com.test.L"), for: app)
        waitForExpectations(timeout: 1)
    }

    func testAddCustomPostsAppRulesChanged() {
        expectation(forNotification: .appRulesChanged, object: nil)
        AppRules.addCustom(CustomApp(name: "ZZNotify2", bundleID: "com.test.n2"))
        waitForExpectations(timeout: 1)
    }

    func testRemovePostsAppRulesChanged() {
        XCTAssertTrue(AppRules.addCustom(CustomApp(name: "ZZNotify3", bundleID: "com.test.n3")))
        guard let app = AppRules.all.first(where: { $0.matchKey == "zznotify3" }) else {
            return XCTFail("custom app not added")
        }
        expectation(forNotification: .appRulesChanged, object: nil)
        AppRules.remove(app)
        waitForExpectations(timeout: 1)
    }
}
