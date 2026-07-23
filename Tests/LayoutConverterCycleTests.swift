import XCTest

// Tests the trilingual+ "cycle" behavior: each conversion targets the NEXT
// enabled layout, and applying it (layout-count) times returns the original.
final class LayoutConverterCycleTests: XCTestCase {

    private static let order = Array("qwertyuiopasdfghjklzxcvbnm")
    private func makeLayout(_ id: String, _ keys: [String]) -> LayoutMap {
        var table: [UInt16: String] = [:]
        for (i, c) in keys.enumerated() { table[UInt16(i)] = c }
        return LayoutMap(sourceID: id, keyToChar: table)
    }
    private func split(_ s: String) -> [String] { s.map(String.init) }

    private lazy var en = makeLayout("ABC", split("qwertyuiopasdfghjklzxcvbnm"))
    private lazy var he = makeLayout("HE",  split("/'קראטוןםפשדגכעיחלךזסבהנמצ"))
    private lazy var ru = makeLayout("RU",  split("йцукенгшщзфывапролдячсмить"))
    private lazy var maps = [en, he, ru]   // EN → HE → RU → EN

    // First press goes to the NEXT layout (HE), not straight to RU.
    func testTargetsNextLayout() {
        let r = LayoutConverter.convert("ghbdtn", maps: maps, currentSourceID: nil)!
        XCTAssertEqual(r.targetSourceID, "HE")
    }

    // Source is detected from the script, target is the next layout.
    func testSourceFromScriptThenNext() {
        let heText = LayoutConverter.convert("ghbdtn", maps: maps, currentSourceID: nil)!.converted
        let r = LayoutConverter.convert(heText, maps: maps, currentSourceID: nil)!
        XCTAssertEqual(r.targetSourceID, "RU")   // HE source → RU next
    }

    // The defining invariant: applying convert (count) times returns the original,
    // visiting every layout in order.
    func testCycleReturnsToOrigin() {
        let original = "ghbdtn"
        var text = original
        var current: String? = "ABC"
        var visited: [String] = []
        for _ in 0..<maps.count {
            let r = LayoutConverter.convert(text, maps: maps, currentSourceID: current)!
            text = r.converted
            current = r.targetSourceID
            visited.append(r.targetSourceID!)
        }
        XCTAssertEqual(visited, ["HE", "RU", "ABC"])
        XCTAssertEqual(text, original, "cycling all layouts must return the original text")
    }

    // Two-layout behavior is unchanged (superset claim).
    func testTwoLayoutIsClassicToggle() {
        XCTAssertEqual(LayoutConverter.convert("ghbdtn", maps: [en, ru], currentSourceID: nil)!.targetSourceID, "RU")
        XCTAssertEqual(LayoutConverter.convert("привет", maps: [en, ru], currentSourceID: nil)!.targetSourceID, "ABC")
        XCTAssertEqual(LayoutConverter.convert("ghbdtn", maps: [en, ru], currentSourceID: nil)!.converted, "привет")
    }

    // Fuzz the cycle-to-origin invariant over many random words.
    func testFuzzCycleReturnsToOrigin() {
        struct LCG: RandomNumberGenerator {
            var s: UInt64
            mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
        }
        var rng = LCG(s: 0xC0FFEE_1234_5678)
        let latin = Array("qwertyuiopasdfghjklzxcvbnm")
        for _ in 0..<5_000 {
            var original = ""
            for _ in 0..<Int.random(in: 1...12, using: &rng) {
                original.append(latin[Int.random(in: 0..<latin.count, using: &rng)])
            }
            var text = original
            var current: String? = "ABC"
            for _ in 0..<maps.count {
                let r = LayoutConverter.convert(text, maps: maps, currentSourceID: current)!
                text = r.converted
                current = r.targetSourceID
            }
            XCTAssertEqual(text, original, "cycle did not return '\(original)'")
        }
    }
}
