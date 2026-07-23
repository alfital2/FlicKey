import XCTest

// Edge cases for the on-screen-span rewrite, from the 2026-07-19 QA sweep
// (docs/united_doc.md F1–F6), adapted after verification and the follow-up fixes:
//
//   FIXED     — shrink (F3): a measured span smaller than tracked is now trusted
//               (deleting less than tracked can never eat prior text).
//   FIXED     — NBSP (F4): any whitespace separates words in the walk.
//   SAFER     — word-split (F2): under-deletes (an orphan the user sees and can
//               fix) instead of over-deleting the user's prior text.
//   DEFERRED  — multi-word expansion (F1): the span is word-count-based, so the
//               expansion's extra words survive, and the residue self-check
//               validates execution against the PLAN, so a plan-level miss stays
//               undetected at runtime. The real fix AND detector is a
//               caret-anchored span (record where the run began) — deferred; see
//               the spec's known limitations.
//   FALLBACK  — AX-unreadable (F5): physically unmeasurable; falls back to the
//               tracked count and now logs autoSwitchSpanFallback to the trail.
final class OnScreenSpanEdgeCaseTests: XCTestCase {

    private func len(_ before: String, words: Int) -> Int {
        OnScreenSpan.length(beforeCaret: Array(before), words: words)
    }

    // Mirrors AutoSwitchController.onScreenDeleteCount (private): trust the
    // measured span unless it exceeds the anti-runaway cap; AX-unreadable falls
    // back to the tracked count.
    private func deleteCount(run: String, before: [Character]?) -> Int {
        let tracked = run.count
        guard let before else { return tracked }
        let words = run.split(separator: " ").count
        let onScreen = OnScreenSpan.length(beforeCaret: before, words: words)
        guard onScreen <= tracked * 3 + 24 else { return min(tracked, before.count) }
        return onScreen
    }

    /// Replays the full delete+retype and returns the resulting field text.
    private func rewrite(field: String, run: String, typed: String,
                         axReadable: Bool = true) -> String {
        let n = deleteCount(run: run, before: axReadable ? Array(field) : nil)
        var chars = Array(field)
        chars.removeLast(min(n, chars.count))
        return String(chars) + typed
    }

    // MARK: - Shrinking mutations (F3 — FIXED)

    func testAutocorrectShrinksADoubledLetter() {
        // "helllo" → "hello": the measured span (11) is exactly right; the old
        // ≥-tracked guard rejected it and the fallback ate one char of prior text.
        XCTAssertEqual(rewrite(field: "keep this hello vnmc ", run: "helllo vnmc ", typed: "מה המצב "),
                       "keep this מה המצב ")
    }

    // MARK: - Non-ASCII whitespace (F4 — FIXED)

    func testNonBreakingSpaceIsTreatedAsASeparator() {
        XCTAssertEqual(rewrite(field: "hi בשמאל\u{00A0}ן ", run: "בשמ ן ", typed: "can i "),
                       "hi can i ")
    }

    // MARK: - Word-split (F2 — SAFER direction, not full fix)

    func testAutocorrectWordSplitUnderDeletesInsteadOfEatingPriorText() {
        // "abcde" → "ab cde": the walk misses the extra group, span (9) < tracked
        // (11). Trusting the smaller span leaves the "ab " orphan (flagged by the
        // residue check) — but never deletes the user's prior text, which the old
        // tracked-count fallback did ("hi aמה המצב ").
        let out = rewrite(field: "hi ab cde vnmc ", run: "abcde vnmc ", typed: "מה המצב ")
        XCTAssertEqual(out, "hi ab מה המצב ")
        XCTAssertTrue(out.hasPrefix("hi "), "prior text must never be eaten")
    }

    // MARK: - Multi-word expansion (F1 — DEFERRED: documented limitation)

    func testTextReplacementExpansionRemainsAKnownLimitation() {
        // Text replacement omw → "On my way!": the walk consumes only two word
        // groups, so "On my " survives. The residue self-check validates the
        // rewrite against its own PLAN, and here the plan itself was short — so
        // this stays silent at runtime too. Both facts pinned; the fix (and the
        // detector) is the deferred caret-anchored span.
        let out = rewrite(field: "On my way! vnmc ", run: "omw vnmc ", typed: "מה המצב ")
        XCTAssertEqual(out, "On my מה המצב ")   // the limitation
        let planned = String(Array("On my way! vnmc ").dropLast(
            deleteCount(run: "omw vnmc ", before: Array("On my way! vnmc ")))) + "מה המצב "
        XCTAssertNil(RewriteCheck.residueAnomaly(actual: Array(out),
                                                 expected: Array(planned),
                                                 typed: Array("מה המצב ")),
                     "execution matched the (short) plan — undetected by design, until caret anchoring")
    }

    // The detector primitive CAN see a space-separated orphan when the true
    // intent is known (the F6 blindness of the old tail heuristic is gone) — this
    // is what makes execution-divergence orphans visible (paced fields dropping
    // synthetic events, over-deletes).
    func testResidueDetectorSeesSpaceSeparatedOrphansGivenIntent() {
        XCTAssertEqual(RewriteCheck.residueAnomaly(actual: Array("On my מה המצב "),
                                                   expected: Array("מה המצב "),
                                                   typed: Array("מה המצב ")),
                       .orphanFragment)
    }

    // MARK: - AX-unreadable fallback (F5 — unmeasurable; falls back + logs)

    func testAXUnreadableFallsBackToTrackedCount() {
        // Without an AX reading there is nothing to measure: the tracked count is
        // the only option, and an autocorrect expansion then leaves the BUG-1
        // orphan. The controller logs autoSwitchSpanFallback(axUnreadable) so the
        // shipping trail shows the unprotected path was taken.
        XCTAssertEqual(rewrite(field: "מה המצב בשמאל ן ", run: "בשמ ן ", typed: "can i ",
                               axReadable: false),
                       "מה המצב בשcan i ")   // documents the fallback's limitation
    }

    // MARK: - Residue check (F6 — FIXED: space-separated orphans visible)

    private func residue(_ actual: String, expected: String, typed: String) -> RewriteAnomalyKind? {
        RewriteCheck.residueAnomaly(actual: Array(actual), expected: Array(expected),
                                    typed: Array(typed))
    }

    func testSpaceSeparatedOrphanIsDetected() {
        XCTAssertEqual(residue("On my מה המצב ", expected: "מה המצב ", typed: "מה המצב "),
                       .orphanFragment)
    }

    func testEatenPrefixIsDetected() {
        XCTAssertEqual(residue("keep thisמה המצב ", expected: "keep this מה המצב ", typed: "מה המצב "),
                       .orphanFragment)
    }

    func testMutatedReplacementIsDetected() {
        XCTAssertEqual(residue("Vimc vmmc ", expected: "vnmc vnmc ", typed: "vnmc vnmc "),
                       .tailMutated)
    }

    func testExactResidueIsClean() {
        XCTAssertNil(residue("prefix מה המצב ", expected: "prefix מה המצב ", typed: "מה המצב "))
    }
}
