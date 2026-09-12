import XCTest

final class InputMemoryTests: XCTestCase {
    private let persistentKey = "appLastUsedInputSources"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: persistentKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: persistentKey)
    }

    func testPersistentMemoryUsesCaseInsensitiveIdentity() {
        AppLastUsedInputStore.set("layout.one", for: "COM.TEST.Editor")
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "com.test.editor"), "layout.one")
        AppLastUsedInputStore.set("layout.two", for: "com.test.editor")
        XCTAssertEqual(AppLastUsedInputStore.sourceID(for: "COM.TEST.EDITOR"), "layout.two")
    }

    func testRetiredSessionRuleMigratesToFixedDefault() {
        XCTAssertEqual(InputRule(storage: "__session__:com.apple.keylayout.Swedish-Pro"),
                       .source("com.apple.keylayout.Swedish-Pro"))
        XCTAssertNil(InputRule(storage: "__session__:"))
    }
}
