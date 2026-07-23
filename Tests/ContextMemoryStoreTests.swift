import XCTest

final class ContextMemoryStoreTests: XCTestCase {

    private let ns = "teams"
    private let other = "slack"

    override func setUp() {
        super.setUp()
        // Start from a clean slate for the keys these tests touch.
        UserDefaults.standard.removeObject(forKey: "conversationInputMemory")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "conversationInputMemory")
        super.tearDown()
    }

    func testSetAndGet() {
        ContextMemoryStore.set("com.apple.keylayout.Hebrew-PC", namespace: ns, key: "הצוות המנצח (External)")
        XCTAssertEqual(
            ContextMemoryStore.sourceID(namespace: ns, key: "הצוות המנצח (External)"),
            "com.apple.keylayout.Hebrew-PC")
    }

    func testUnknownKeyIsNil() {
        XCTAssertNil(ContextMemoryStore.sourceID(namespace: ns, key: "nope"))
    }

    func testOverwrite() {
        ContextMemoryStore.set("A", namespace: ns, key: "k")
        ContextMemoryStore.set("B", namespace: ns, key: "k")
        XCTAssertEqual(ContextMemoryStore.sourceID(namespace: ns, key: "k"), "B")
    }

    func testNamespacesAreIsolated() {
        ContextMemoryStore.set("A", namespace: ns, key: "k")
        ContextMemoryStore.set("B", namespace: other, key: "k")
        XCTAssertEqual(ContextMemoryStore.sourceID(namespace: ns, key: "k"), "A")
        XCTAssertEqual(ContextMemoryStore.sourceID(namespace: other, key: "k"), "B")
    }

    func testPersistsAcrossReadsViaUserDefaults() {
        ContextMemoryStore.set("X", namespace: ns, key: "k")
        // Round-trip through the raw dictionary to confirm the on-disk shape.
        let raw = UserDefaults.standard.dictionary(forKey: "conversationInputMemory") as? [String: [String: String]]
        XCTAssertEqual(raw?[ns]?["k"], "X")
    }
}
