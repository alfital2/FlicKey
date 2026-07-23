import XCTest

final class SiteMemoryStoreTests: XCTestCase {

    override func setUp() { UserDefaults.standard.removeObject(forKey: "siteInputMemory") }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: "siteInputMemory") }

    func testSetThenGet() {
        SiteMemoryStore.set("com.apple.keylayout.Hebrew-PC", for: "bankotsar.co.il")
        XCTAssertEqual(SiteMemoryStore.sourceID(for: "bankotsar.co.il"),
                       "com.apple.keylayout.Hebrew-PC")
    }

    func testUnknownDomainReturnsNil() {
        XCTAssertNil(SiteMemoryStore.sourceID(for: "never-set.com"))
    }

    func testOverwrite() {
        SiteMemoryStore.set("a", for: "x.com")
        SiteMemoryStore.set("b", for: "x.com")
        XCTAssertEqual(SiteMemoryStore.sourceID(for: "x.com"), "b")
    }

    func testClear() {
        SiteMemoryStore.set("a", for: "x.com")
        SiteMemoryStore.clear("x.com")
        XCTAssertNil(SiteMemoryStore.sourceID(for: "x.com"))
    }

    func testDistinctDomainsIndependent() {
        SiteMemoryStore.set("a", for: "one.com")
        SiteMemoryStore.set("b", for: "two.com")
        XCTAssertEqual(SiteMemoryStore.sourceID(for: "one.com"), "a")
        XCTAssertEqual(SiteMemoryStore.sourceID(for: "two.com"), "b")
    }
}
