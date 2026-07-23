import XCTest

// Multi-layout candidate conversion for auto-switch: with three layouts enabled,
// a wrong-layout word must be able to reach EVERY other layout, so the one that
// spells a real word can win. Fixtures use the real key mappings, verified with
// UCKeyTranslate dumps of the installed layouts.
final class LayoutConverterCandidatesTests: XCTestCase {

    private static let order = Array("qwertyuiopasdfghjklzxcvbnm")

    private func makeLayout(_ id: String, _ keys: [String]) -> LayoutMap {
        precondition(keys.count == Self.order.count)
        var table: [UInt16: String] = [:]
        for (i, char) in keys.enumerated() { table[UInt16(i)] = char }
        return LayoutMap(sourceID: id, keyToChar: table)
    }
    private func split(_ s: String) -> [String] { s.map(String.init) }

    private lazy var english = makeLayout("ABC", split("qwertyuiopasdfghjklzxcvbnm"))
    private lazy var russian = makeLayout("RU",  split("йцукенгшщзфывапролдячсмить"))
    private lazy var hebrew  = makeLayout("HE",  split("/'קראטוןםפשדגכעיחלךזסבהנמצ"))

    private var maps: [LayoutMap] { [english, russian, hebrew] }

    func testCandidatesReachEveryOtherLayout() {
        let candidates = LayoutConverter.candidates("ghbdtn", maps: maps, currentSourceID: nil)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map { $0.targetSourceID }, ["RU", "HE"])
        XCTAssertTrue(candidates.contains { $0.converted == "привет" && $0.targetSourceID == "RU" })
    }

    func testCandidatesDetectNonLatinSource() {
        // A Hebrew word offers Latin and Cyrillic readings; the Latin one is the
        // classic gibberish swap.
        let candidates = LayoutConverter.candidates("שלום", maps: maps, currentSourceID: nil)
        XCTAssertEqual(candidates.map { $0.targetSourceID }, ["ABC", "RU"])
        XCTAssertTrue(candidates.contains { $0.converted == "akuo" && $0.targetSourceID == "ABC" })
    }

    func testConvertToSpecificTarget() {
        let result = LayoutConverter.convert("ghbdtn", toSourceID: "RU", maps: maps, currentSourceID: nil)
        XCTAssertEqual(result?.converted, "привет")
        XCTAssertEqual(result?.targetSourceID, "RU")
    }

    func testConvertToSourceItselfIsNil() {
        XCTAssertNil(LayoutConverter.convert("привет", toSourceID: "RU", maps: maps, currentSourceID: nil))
    }

    func testConvertToUnknownTargetIsNil() {
        XCTAssertNil(LayoutConverter.convert("ghbdtn", toSourceID: "GR", maps: maps, currentSourceID: nil))
    }

    func testAmbiguousTextFallsBackToCurrentLayoutAsSource() {
        // Pure punctuation has no exclusive characters; the current layout decides.
        let candidates = LayoutConverter.candidates("...", maps: maps, currentSourceID: "RU")
        XCTAssertEqual(candidates.map { $0.targetSourceID }, ["ABC", "HE"])
    }

    func testAmbiguousTextWithUnknownCurrentHasNoCandidates() {
        XCTAssertTrue(LayoutConverter.candidates("...", maps: maps, currentSourceID: nil).isEmpty)
    }
}
