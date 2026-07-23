import XCTest

final class OnScreenSpanTests: XCTestCase {

    private func len(_ before: String, words: Int) -> Int {
        OnScreenSpan.length(beforeCaret: Array(before), words: words)
    }

    func testNoAutocorrectMatchesTrackedLength() {
        // "abc de " — two words, nothing expanded → span == the run's own length.
        XCTAssertEqual(len("abc de ", words: 2), "abc de ".count)
    }

    func testAutocorrectExpansionMeasuresTheRealSpan() {
        // The reported bug: run "te cat " but autocorrect expanded "te"→"teh" on
        // screen, behind a preserved prefix "hi ". The span must cover the real
        // "teh cat " (8), not the tracked "te cat " (7), so nothing is orphaned.
        XCTAssertEqual(len("hi teh cat ", words: 2), "teh cat ".count)   // 8
    }

    func testHebrewExpansionCase() {
        // The exact repro shape: prefix "מה המצב ", run "בשמ ן " expanded to
        // "בשמאל ן " on screen. Span must be the on-screen 8, leaving the prefix.
        XCTAssertEqual(len("מה המצב בשמאל ן ", words: 2), "בשמאל ן ".count)   // 8
    }

    func testPrefixIsNeverConsumed() {
        // Whatever the span is, it must not reach into the preserved prefix.
        let span = len("keep this מה המצב בשמאל ן ", words: 2)
        XCTAssertEqual(span, "בשמאל ן ".count)
    }

    func testSingleWord() {
        XCTAssertEqual(len("hello world ", words: 1), "world ".count)     // 6
    }

    func testThreeWords() {
        XCTAssertEqual(len("pre one two three ", words: 3), "one two three ".count)
    }

    func testZeroWordsIsZero() {
        XCTAssertEqual(len("anything here ", words: 0), 0)
    }

    func testEmptyBeforeCaret() {
        XCTAssertEqual(len("", words: 2), 0)
    }

    func testWalkRunningPastStartStopsCleanly() {
        // Field has fewer words than the run claims (stale/odd read) — must not
        // crash and must not exceed the available characters.
        let span = len("one ", words: 5)
        XCTAssertEqual(span, "one ".count)
    }

    func testMultipleSpacesBetweenWords() {
        // Defensive: collapsed/double spaces shouldn't miscount the word walk.
        XCTAssertEqual(len("a  bb  cc ", words: 2), "bb  cc ".count)
    }

    func testNonBreakingSpaceSeparatesWords() {
        // A text service can substitute U+00A0 for a typed space; treating it as a
        // word character walked past the run into prior text (QA F4).
        XCTAssertEqual(len("hi בשמאל\u{00A0}ן ", words: 2), "בשמאל\u{00A0}ן ".count)
    }

    // MARK: - RewriteCheck (post-rewrite self-check)

    private func anomaly(_ before: String, expected: String) -> RewriteAnomalyKind? {
        RewriteCheck.anomaly(beforeCaret: Array(before), expected: Array(expected))
    }

    func testCleanRewriteHasNoAnomaly() {
        XCTAssertNil(anomaly("מה המצב can i ", expected: "can i "))
    }

    func testReplacementAsWholeContentIsClean() {
        XCTAssertNil(anomaly("can i ", expected: "can i "))
    }

    func testOrphanFragmentDetected() {
        // BUG-1 shape: a stale "בש" fused before the replacement.
        XCTAssertEqual(anomaly("מה המצב בשcan i ", expected: "can i "), .orphanFragment)
    }

    func testTailMutationDetected() {
        // BUG-2 shape: the retyped original was re-mutated by autocorrect.
        XCTAssertEqual(anomaly("Vimc vmmc ", expected: "vnmc vnmc "), .tailMutated)
    }

    func testEmptyExpectedIsClean() {
        XCTAssertNil(anomaly("anything ", expected: ""))
    }
}
