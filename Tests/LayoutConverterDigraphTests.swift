import XCTest

// QA ARABIC-1: ArabicPC (and Arabic-AZERTY) put the mandatory lam-alef ligature
// لا — TWO characters from ONE key — on the b key. A per-character reverse walk
// can never match it, so typed-as-b text couldn't convert back ("bad" → لاشي →
// "ghad"). But the pair is genuinely AMBIGUOUS: ل+ا also arises from the g and h
// keys, and greedily collapsing it would corrupt every English word containing
// "gh" (high, night…) — the converter fuzz suite caught exactly that. So the
// resolution is parse candidates: the per-character reading stays the default,
// the digraph-greedy reading is offered alongside it, and a dictionary picks.
final class LayoutConverterDigraphTests: XCTestCase {

    // Keycodes mirror the real positions: a=0, b=11, c=8, d=2, g=5, h=4, t=17.
    private let abc = LayoutMap(sourceID: "ABC", keyToChar: [
        0: "a", 11: "b", 8: "c", 2: "d", 5: "g", 4: "h", 17: "t",
    ])
    private let arabic = LayoutMap(sourceID: "AR", keyToChar: [
        0: "ش", 11: "لا", 8: "ؤ", 2: "ي", 5: "ل", 4: "ا", 17: "ف",
    ])

    // MARK: - Both readings are offered

    func testParsesOfferBothReadingsForDigraphText() {
        XCTAssertEqual(LayoutConverter.parses(of: "لاشي", from: arabic, to: abc),
                       ["ghad", "bad"])
    }

    func testParsesCollapseWhenNoDigraphIsInvolved() {
        XCTAssertEqual(LayoutConverter.parses(of: "شي", from: arabic, to: abc), ["ad"])
    }

    func testCandidatesIncludeTheDigraphReading() {
        let candidates = LayoutConverter.candidates("لاشي", maps: [abc, arabic],
                                                    currentSourceID: nil).map(\.converted)
        XCTAssertTrue(candidates.contains("bad"), "the b-key reading must be offered")
        XCTAssertTrue(candidates.contains("ghad"), "the per-character reading must be offered")
    }

    // MARK: - The dictionary chooses (the auto-switch fire path)

    func testPreferringValidatorPicksTheRealWord() {
        let real: Set<String> = ["bad", "cat"]
        let result = LayoutConverter.convert("لاشي", toSourceID: "ABC",
                                             maps: [abc, arabic], currentSourceID: nil,
                                             preferring: { real.contains($0) })
        XCTAssertEqual(result?.converted, "bad")
    }

    func testPreferringValidatorKeepsPerCharacterOnTie() {
        // Neither reading validates → the per-character default wins (today's
        // behavior everywhere a digraph isn't involved).
        let result = LayoutConverter.convert("لاشي", toSourceID: "ABC",
                                             maps: [abc, arabic], currentSourceID: nil,
                                             preferring: { _ in false })
        XCTAssertEqual(result?.converted, "ghad")
    }

    func testMultiWordRunPicksTheReadingWithMoreRealWords() {
        // The QA's live case: "bad cat " typed on ArabicPC. Whole-run conversion
        // must follow the dictionary-validated reading, or the fire would type
        // "ghad cat" after the classifier approved "bad".
        let real: Set<String> = ["bad", "cat"]
        let result = LayoutConverter.convert("لاشي ؤشف", toSourceID: "ABC",
                                             maps: [abc, arabic], currentSourceID: nil,
                                             preferring: { real.contains($0) })
        XCTAssertEqual(result?.converted, "bad cat")
    }

    // MARK: - Forward direction and gh-safety

    func testEnglishToArabicProducesTheDigraph() {
        // Per-character forward: b → key 11 → لا (a 1→2 mapping, naturally).
        XCTAssertEqual(LayoutConverter.convert("bad", between: abc, and: arabic,
                                               currentSourceID: "ABC").converted, "لاشي")
    }

    func testGhWordsSurviveRoundTrip() {
        // "high" → e.g. اهلا? typed g+h produce ل+ا adjacently; converting back
        // per-character must NOT collapse them into b (the fuzz-caught regression).
        let toAr = LayoutConverter.convert("gh", between: abc, and: arabic,
                                           currentSourceID: "ABC").converted
        XCTAssertEqual(toAr, "لا")
        let back = LayoutConverter.convert(toAr, between: arabic, and: abc,
                                           currentSourceID: "AR").converted
        XCTAssertEqual(back, "gh", "per-character default must preserve gh round-trips")
    }
}
