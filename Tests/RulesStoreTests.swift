import XCTest

final class RulesStoreTests: XCTestCase {

    private let keys = ["appInputOverrides", "customApps", "hiddenBuiltins"]
    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    func testOverrideRoundTrip() {
        RulesStore.set("com.apple.keylayout.ABC", forMatchKey: "terminal")
        XCTAssertEqual(RulesStore.overrides()["terminal"], "com.apple.keylayout.ABC")
    }

    func testCustomAppsAddAndRemove() {
        RulesStore.addCustomApp(CustomApp(name: "Notes", bundleID: "com.apple.Notes"))
        XCTAssertEqual(RulesStore.customApps().count, 1)
        RulesStore.removeCustomApp(matchKey: "notes")
        XCTAssertTrue(RulesStore.customApps().isEmpty)
    }

    func testHiddenBuiltinsToggle() {
        RulesStore.hideBuiltin(matchKey: "safari")
        XCTAssertTrue(RulesStore.hiddenBuiltins().contains("safari"))
        RulesStore.unhideBuiltin(matchKey: "safari")
        XCTAssertFalse(RulesStore.hiddenBuiltins().contains("safari"))
    }

    func testRemovingCustomClearsItsOverride() {
        RulesStore.set("x", forMatchKey: "notes")
        RulesStore.removeCustomApp(matchKey: "notes")
        XCTAssertNil(RulesStore.overrides()["notes"])
    }

    func testHidingBuiltinClearsItsOverride() {
        RulesStore.set("x", forMatchKey: "safari")
        RulesStore.hideBuiltin(matchKey: "safari")
        XCTAssertNil(RulesStore.overrides()["safari"])
    }
}
