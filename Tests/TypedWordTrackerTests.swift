import XCTest

final class TypedWordTrackerTests: XCTestCase {

    private func run(_ strokes: [KeyStroke]) -> [String] {
        var acc = WordAccumulator()
        var emitted: [String] = []
        for k in strokes { if let w = acc.feed(k) { emitted.append(w) } }
        return emitted
    }

    private func letters(_ s: String) -> [KeyStroke] { s.map { .letter($0) } }

    func testWordThenSpaceEmitsWord() {
        XCTAssertEqual(run(letters("susu") + [.space]), ["susu"])
    }

    func testHardBreakAlsoEmitsWord() {
        XCTAssertEqual(run(letters("susu") + [.hardBreak]), ["susu"])
    }

    func testTwoWords() {
        let strokes = letters("foo") + [.space] + letters("bar") + [.space]
        XCTAssertEqual(run(strokes), ["foo", "bar"])
    }

    func testNoEmitWithoutSeparator() {
        XCTAssertEqual(run(letters("typing")), [])
    }

    func testEmptyBetweenSeparatorsEmitsNothing() {
        XCTAssertEqual(run([.space, .hardBreak]), [])
    }

    func testBackspaceShortensCurrentWord() {
        // "sudu" backspace ×2 → "su", then "sh" → "sush" + space
        let strokes = letters("sudu") + [.backspace, .backspace] + letters("sh") + [.space]
        XCTAssertEqual(run(strokes), ["sush"])
    }

    func testBackspaceOnEmptyIsSafe() {
        XCTAssertEqual(run([.backspace] + letters("hi") + [.space]), ["hi"])
    }

    func testResetClearsWithoutEmitting() {
        var acc = WordAccumulator()
        _ = acc.feed(.letter("h")); _ = acc.feed(.letter("i"))
        acc.reset()
        XCTAssertEqual(acc.current, "")
        XCTAssertNil(acc.feed(.space))
    }

    // MARK: - Raw run buffer (for auto-switch reconstruction)

    private func runBuffer(_ strokes: [KeyStroke]) -> String {
        var acc = WordAccumulator()
        for k in strokes { _ = acc.feed(k) }
        return acc.run
    }

    func testRunAccumulatesLettersAndSpaces() {
        XCTAssertEqual(runBuffer(letters("ab") + [.space] + letters("cd")), "ab cd")
    }

    func testRunContinuesAcrossASoftSpaceWord() {
        // Two words separated by a space stay in one run, trailing space included.
        let strokes = letters("akuo") + [.space] + letters("okuo") + [.space]
        XCTAssertEqual(runBuffer(strokes), "akuo okuo ")
    }

    func testRunBackspaceRemovesLastChar() {
        XCTAssertEqual(runBuffer(letters("abc") + [.backspace]), "ab")
    }

    func testHardBreakClearsRun() {
        let strokes = letters("ab") + [.space] + letters("cd") + [.hardBreak]
        XCTAssertEqual(runBuffer(strokes), "")
    }

    func testResetClearsRun() {
        var acc = WordAccumulator()
        _ = acc.feed(.letter("h")); _ = acc.feed(.space)
        acc.reset()
        XCTAssertEqual(acc.run, "")
    }

    func testResetRunKeepingSeedsTheNewStreak() {
        var acc = WordAccumulator()
        for k in letters("ab") + [.space] + letters("cd") + [.space] { _ = acc.feed(k) }
        acc.resetRun(keeping: "cd ")
        XCTAssertEqual(acc.run, "cd ")
    }

    // MARK: - Word/run coherence (the word is always the run's tail)

    func testBackspacingAcrossAWordBoundaryRejoinsTheWord() {
        // "ab " then deleting the space and 'b', then typing "x ": the screen tail
        // is "ax", so the emitted word must be "ax", not the fragment "x".
        let strokes = letters("ab") + [.space, .backspace, .backspace] + letters("x") + [.space]
        XCTAssertEqual(run(strokes), ["ab", "ax"])
    }

    func testCurrentAlwaysMatchesTheRunTail() {
        var acc = WordAccumulator()
        for k in letters("ab") + [.space, .backspace] { _ = acc.feed(k) }
        XCTAssertEqual(acc.run, "ab")
        XCTAssertEqual(acc.current, "ab")   // deleting the space rejoined the word
    }

    // MARK: - Multi-character key output (ArabicPC b → لا)

    func testMultiCharacterOutputFeedsEachLetter() {
        XCTAssertEqual(TypedWordTracker.strokes(forOutput: "لا"),
                       [.letter("ل"), .letter("ا")])
    }

    func testSingleCharacterOutputStillClassifies() {
        XCTAssertEqual(TypedWordTracker.strokes(forOutput: "a"), [.letter("a")])
        XCTAssertEqual(TypedWordTracker.strokes(forOutput: " "), [.space])
        XCTAssertEqual(TypedWordTracker.strokes(forOutput: "!"), [.hardBreak])
    }

    func testMixedMultiCharacterOutputFallsBackToHardBreak() {
        // Unknown multi-char output that isn't all word characters ends the run
        // rather than guessing.
        XCTAssertEqual(TypedWordTracker.strokes(forOutput: "a!"), [.hardBreak])
    }

    // MARK: - Character → KeyStroke classification

    func testLettersAndSpaceClassification() {
        XCTAssertEqual(TypedWordTracker.stroke(forCharacter: "a"), .letter("a"))
        XCTAssertEqual(TypedWordTracker.stroke(forCharacter: "ש"), .letter("ש"))
        XCTAssertEqual(TypedWordTracker.stroke(forCharacter: " "), .space)
    }

    func testLayoutPunctuationCountsAsWordCharacter() {
        // Keys that carry a letter on some layout: Hebrew ת ץ ף on , . ;, Russian
        // б ю ж э х ъ ё on , . ; ' [ ] \, Arabic و ز ك ط ج د on , . ; ' [ ].
        for ch: Character in [",", ".", ";", "'", "/", "`", "[", "]", "\\"] {
            XCTAssertEqual(TypedWordTracker.stroke(forCharacter: ch), .letter(ch), "\(ch) should be a word char")
        }
    }

    func testGereshVariantsAndArabicPunctuationAreWordCharacters() {
        // The non-PC Hebrew layouts put ׳ (U+05F3) and ’ (U+2019) on the geresh
        // keys, and Arabic layouts put ، ؛ on letter-adjacent keys; all must stay
        // inside a wrong-layout word for detection to see them.
        for ch: Character in ["\u{05F3}", "\u{2019}", "\u{060C}", "\u{061B}"] {
            XCTAssertEqual(TypedWordTracker.stroke(forCharacter: ch), .letter(ch), "\(ch) should be a word char")
        }
    }

    func testOtherPunctuationAndDigitsEndTheWord() {
        for ch: Character in ["!", "?", "-", "5", ")"] {
            XCTAssertEqual(TypedWordTracker.stroke(forCharacter: ch), .hardBreak, "\(ch) should end the word")
        }
    }

    func testCommaWordStaysWhole() {
        // "t,nuk" (→ אתמול) must survive as a single word, comma included.
        let strokes = "t,nuk".map { TypedWordTracker.stroke(forCharacter: $0) } + [.space]
        XCTAssertEqual(run(strokes), ["t,nuk"])
    }
}
