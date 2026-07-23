import XCTest

final class OrthographyRulesTests: XCTestCase {

    // MARK: - Hebrew geresh (ported from the HebrewGeresh unit it generalizes)

    func testLegitimateGereshAfterLoanLetters() {
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("ג'ז"))     // jazz
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("צ'יפס"))   // chips
    }

    func testIllegitimateGereshFlags() {
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("ים'"))      // ' after ם
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("'אבג"))     // leading '
    }

    func testTypographicGereshVariantsCovered() {
        // The Hebrew and Hebrew-QWERTY layouts produce ׳ (U+05F3) and ’ (U+2019)
        // on the same keys the PC layout puts ' on.
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("ים\u{05F3}"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("ג\u{05F3}ז"))
    }

    // MARK: - Hebrew final forms (ך ם ן ף ץ only appear word-finally)

    func testHebrewFinalFormMidWordFlags() {
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("מםא"))    // "not" typed on Hebrew: ם mid-word
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("יקךךם"))  // "hello": ך twice mid-word
    }

    func testHebrewFinalFormAtEndIsFine() {
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("שלום"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("דם"))
    }

    func testHebrewFinalPlusGereshEndingIsFine() {
        // Loanwords end in a final form + geresh: סנדוויץ' (sandwich).
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("סנדוויץ'"))
    }

    func testHebrewFinalFollowedByGluedPunctuationIsFine() {
        // The tracker glues layout-punctuation into words, so a sentence-final
        // Hebrew word arrives as "שלום." — the ם is still effectively final.
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("שלום."))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("דם,"))
    }

    func testHebrewZayinGereshLoanwordsAreLegit() {
        // ז' spells the zh sound in loanwords: ז'קט (jacket), ז'אנר (genre).
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("ז'קט"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("ז'אנר"))
    }

    func testHebrewNonFinalAtEndIsNotFlagged() {
        // Loanwords legitimately end in non-final letters (צ'יפ); only the
        // impossible direction (final form mid-word) is a tell.
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("צ'יפ"))
    }

    // MARK: - Greek (ς word-final only; the q-key erotimatiko never starts/joins)

    func testGreekFinalSigmaMidWordFlags() {
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("τςο"))    // "two" typed on Greek
    }

    func testGreekFinalSigmaAtEndIsFine() {
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("πες"))
    }

    func testGreekSemicolonInWordFlags() {
        // 'q' on the Greek layout produces the erotimatiko, so "quick" becomes
        // ";θιψκ" — a ; inside a Greek-script word is a slip signature.
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell(";θιψκ"))
    }

    func testGreekQuestionsAreLegit() {
        // A real Greek question glues its erotimatiko to the word (the tracker
        // keeps ; inside words): κάνεις; and τι; must not be flagged — neither by
        // the ; tell (nothing follows it) nor by the ς rule (it is still the last
        // LETTER even with the ; after it).
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("κάνεις;"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("τι;"))
    }

    // MARK: - Arabic (ة and ى word-final only; Arabic comma/semicolon never intra-word)

    func testArabicTaaMarbutaMidWordFlags() {
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("سةشمم"))  // "small" on ArabicPC
    }

    func testArabicFinalsAtEndAreFine() {
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("مدرسة")) // school
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("مستشفى")) // hospital
    }

    func testArabicPunctuationInsideWordFlags() {
        // "don't" typed on the Arabic layout embeds the Arabic semicolon.
        XCTAssertTrue(OrthographyRules.hasWrongLayoutTell("يخر\u{061B}ف"))
    }

    func testArabicTrailingPunctuationIsLegit() {
        // A sentence comma glued to the word's end is ordinary Arabic writing.
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("كتاب\u{060C}"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("مدرسة\u{060C}"))
    }

    // MARK: - Scripts with no structural tell

    func testCyrillicAndLatinNeverTell() {
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("привет"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("объём"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("don't"))
        XCTAssertFalse(OrthographyRules.hasWrongLayoutTell("hello"))
    }
}
