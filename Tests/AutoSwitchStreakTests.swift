import XCTest

final class AutoSwitchStreakTests: XCTestCase {

    private func wrong(_ target: String? = "HE", single: Bool = false) -> AutoSwitchStreak.Word {
        .wrongLayout(targetSourceID: target, isSingleLetter: single)
    }
    private func amb(_ target: String? = "HE") -> AutoSwitchStreak.Word {
        .ambiguousLayout(targetSourceID: target)
    }

    func testSingleWrongWordDoesNotArm() {
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong()))
    }

    func testTwoWrongInARowArms() {
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong()))
        XCTAssertTrue(s.word(wrong()))
    }

    func testStaysArmedWhileWrongWordsContinue() {
        // A continuously typed wrong phrase keeps the fire armed so the WHOLE run
        // converts when typing pauses, not just the first pair.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong()))
        XCTAssertTrue(s.word(wrong()))
        XCTAssertTrue(s.word(wrong()))
        XCTAssertTrue(s.word(wrong()))
    }

    func testBreakRunDisarms() {
        // fire() calls breakRun() after rewriting; a fresh streak starts over.
        var s = AutoSwitchStreak()
        _ = s.word(wrong())
        XCTAssertTrue(s.word(wrong()))
        s.breakRun()
        XCTAssertFalse(s.word(wrong()))
        XCTAssertTrue(s.word(wrong()))
    }

    func testOrdinaryWordBreaksTheStreak() {
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong()))
        XCTAssertFalse(s.word(.ordinary))       // resets
        XCTAssertFalse(s.word(wrong()))         // streak restarts at 1
        XCTAssertTrue(s.word(wrong()))
    }

    // MARK: - Target agreement

    func testDisagreeingTargetsRestartTheCount() {
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong("RU")))
        XCTAssertFalse(s.word(wrong("HE")))     // different target: restart at 1
        XCTAssertTrue(s.word(wrong("HE")))      // now two agreeing → arm
        XCTAssertEqual(s.targetSourceID, "HE")
    }

    func testTargetReadableWhileArmed() {
        var s = AutoSwitchStreak()
        _ = s.word(wrong("RU"))
        XCTAssertTrue(s.word(wrong("RU")))
        XCTAssertEqual(s.targetSourceID, "RU")
    }

    // MARK: - Single letters

    func testSingleLetterCanOpenAStreakButPairNeedsAMultiLetterWord() {
        // "ן גםמא" (i dont): the lone letter opens, the multi-letter word arms.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong(single: true)))
        XCTAssertTrue(s.word(wrong()))
    }

    func testAllSingleLetterStreakNeverArms() {
        // "b d" typed in English maps to valid Russian single-letter words; a
        // streak made only of lone letters must never rewrite text.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong(single: true)))
        XCTAssertFalse(s.word(wrong(single: true)))
        XCTAssertFalse(s.word(wrong(single: true)))
    }

    func testMultiLetterWordThenSingleArms() {
        // The original "can i" case.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong()))
        XCTAssertTrue(s.word(wrong(single: true)))
    }

    func testLateMultiLetterWordArmsAnAllSingleStreak() {
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(wrong(single: true)))
        XCTAssertFalse(s.word(wrong(single: true)))
        XCTAssertTrue(s.word(wrong()))          // count 3, multi present → arm
    }

    // MARK: - Ambiguous words (valid as typed AND once converted)

    func testAmbiguousWordKeepsAnArmedStreakAlive() {
        // The reported bug: "gbv amrhl kvuxh; t, zv" (ענה שצריך להוסיף את זה). את reads
        // as the valid English-ish token "t," (notSlip) but is a real Hebrew word; once
        // the run is armed by real matches it must NOT disarm mid-sentence.
        var s = AutoSwitchStreak()
        _ = s.word(wrong())
        XCTAssertTrue(s.word(wrong()))          // armed by two confident matches
        XCTAssertTrue(s.word(amb()), "a real-word ambiguous token mid-run must not disarm")
        XCTAssertTrue(s.word(wrong()))          // stays armed through the rest
    }

    func testAmbiguousOpenerNeedsTwoConfidentMatchesToArm() {
        // "fi t,v hfuk" (כן אתה יכול): the leading כן ("fi") is ambiguous and rides in the
        // run, but arming still needs TWO confident matches — a single one can't sweep it in.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(amb()), "an ambiguous word alone never arms")
        XCTAssertEqual(s.targetSourceID, "HE")  // provisional target set, kept in the run
        XCTAssertFalse(s.word(wrong()), "opener + ONE confident match is not enough")
        XCTAssertTrue(s.word(wrong()), "the second confident match arms; the opener rides in")
    }

    func testAmbiguousPlusOneConfidentMatchNeverArms() {
        // The false positive the adversarial pass found: casual English like "and hes" —
        // "and" (ambiguous, valid Hebrew) + "hes" (one confident match) must NOT arm and
        // rewrite real English into Hebrew.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(amb()))           // "and" → valid Hebrew, ambiguous
        XCTAssertFalse(s.word(wrong()),
                       "one confident match beside an ambiguous word must never arm")
    }

    func testAllAmbiguousStreakNeverArms() {
        // Genuine English that merely happens to also be valid Hebrew ("to go do…") must
        // never convert on its own: with no confident match, the streak can't arm.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(amb()))
        XCTAssertFalse(s.word(amb()))
        XCTAssertFalse(s.word(amb()))
        XCTAssertFalse(s.word(amb()))
    }

    func testAmbiguousWordsRideAnAlreadyArmedRun() {
        // Two confident matches arm; ambiguous words after that stay armed and ride along
        // (so the passage's function words convert with it).
        var s = AutoSwitchStreak()
        _ = s.word(wrong())
        XCTAssertTrue(s.word(wrong()))          // armed by two confident matches
        XCTAssertTrue(s.word(amb()))            // ambiguous rides the armed run
        XCTAssertTrue(s.word(amb()))
    }

    func testAmbiguousWordsAloneThenLateMatchesArm() {
        // Ambiguous words provide neither count-toward-threshold nor confidence; it still
        // takes two confident matches to arm.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(amb()))           // no confidence
        XCTAssertFalse(s.word(amb()))           // still none
        XCTAssertFalse(s.word(wrong()))         // one confident match — not yet
        XCTAssertTrue(s.word(wrong()))          // two confident matches → arm
    }

    func testAmbiguousDisagreeingTargetRestarts() {
        // An ambiguous word toward a different target restarts rather than arming, so a
        // mismatched provisional prefix can't drag the run toward a layout it never matched.
        var s = AutoSwitchStreak()
        _ = s.word(wrong("HE"))
        _ = s.word(amb("HE"))
        XCTAssertFalse(s.word(amb("RU")), "switching target restarts, not arms")
        XCTAssertEqual(s.targetSourceID, "RU")
    }

    func testAmbiguousPlusSingleLetterMatchNeverArms() {
        // Neither an ambiguous word nor a lone-letter match supplies the required
        // confident multi-letter evidence.
        var s = AutoSwitchStreak()
        XCTAssertFalse(s.word(amb()))                 // no confidence
        XCTAssertFalse(s.word(wrong(single: true)))   // one single-letter confident match
    }
}
