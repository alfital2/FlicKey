import XCTest

// Cross-language UPPERCASE handling. Deterministic fixtures (incl. shifted maps)
// reproduce the real-layout bug — Hebrew echoing a Latin capital on shift — and
// prove the fix: cased scripts (Russian) keep the capital, case-less scripts
// (Hebrew) drop it and never leak Latin.
final class LayoutConverterCaseTests: XCTestCase {

    private static let order = Array("qwertyuiopasdfghjklzxcvbnm").map(String.init)

    private func makeLayout(_ id: String, base: [String], shift: [String]) -> LayoutMap {
        var b: [UInt16: String] = [:], s: [UInt16: String] = [:]
        for (i, c) in base.enumerated() { b[UInt16(i)] = c }
        for (i, c) in shift.enumerated() { s[UInt16(i)] = c }
        return LayoutMap(sourceID: id, keyToChar: b, keyToCharShift: s)
    }

    private lazy var english = makeLayout("ABC",
        base: Self.order, shift: Self.order.map { $0.uppercased() })
    private lazy var russian: LayoutMap = {
        let base = Array("йцукенгшщзфывапролдячсмить").map(String.init)
        return makeLayout("RU", base: base, shift: base.map { $0.uppercased() })
    }()
    private lazy var hebrew: LayoutMap = {
        let base = Array("/'קראטוןםפשדגכעיחלךזסבהנמצ").map(String.init)
        // Hebrew has no case — and the real macOS layout echoes a Latin capital
        // on shift. Reproduce that here to guard against the regression.
        return makeLayout("HE", base: base, shift: Self.order.map { $0.uppercased() })
    }()

    func testRussianKeepsCase() {
        XCTAssertEqual(LayoutConverter.convert("a", maps: [english, russian], currentSourceID: nil)?.converted, "ф")
        XCTAssertEqual(LayoutConverter.convert("A", maps: [english, russian], currentSourceID: nil)?.converted, "Ф")
        XCTAssertEqual(LayoutConverter.convert("Privet", maps: [english, russian], currentSourceID: nil)?.converted, "Зкшмуе")
    }

    func testHebrewDropsCaseAndNeverLeaksLatin() {
        // The user is on the English layout when typing these caps, so the active
        // source breaks the (Latin-echo-induced) tie — exactly as in real use.
        let abc = "ABC"
        XCTAssertEqual(LayoutConverter.convert("a", maps: [english, hebrew], currentSourceID: abc)?.converted, "ש")
        XCTAssertEqual(LayoutConverter.convert("A", maps: [english, hebrew], currentSourceID: abc)?.converted, "ש")
        XCTAssertEqual(LayoutConverter.convert("AKUO", maps: [english, hebrew], currentSourceID: abc)?.converted, "שלום")
        let mixed = LayoutConverter.convert("Akuo", maps: [english, hebrew], currentSourceID: abc)?.converted ?? ""
        XCTAssertFalse(mixed.contains { $0.isASCII && $0.isLetter }, "Latin leaked: \(mixed)")
    }
}
