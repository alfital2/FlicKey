import XCTest

// A fake spell checker with an explicit set of FUNCTIONAL languages. Words in
// `valid` are correctly spelled; anything else in a functional language is
// misspelled. A non-functional language flags nothing, mirroring the real
// NSSpellChecker, which lists several languages whose checker cannot fail.
private struct FakeSpellChecker: SpellChecking {
    let valid: [String: Set<String>]
    let functional: Set<String>
    let corrections: [String: String]

    init(valid: [String: Set<String>], functional: Set<String>? = nil,
         corrections: [String: String] = [:]) {
        self.valid = valid
        self.functional = functional ?? Set(valid.keys)
        self.corrections = corrections
    }

    func hasFunctionalDictionary(_ language: String) -> Bool { functional.contains(language) }
    func isMisspelled(_ word: String, language: String) -> Bool {
        functional.contains(language) && !(valid[language]?.contains(word) ?? false)
    }
    func correction(for word: String, language: String) -> String? { corrections[word] }
}

final class WrongLayoutClassifierTests: XCTestCase {

    // A classifier over a single fixed swap pair, the two-layout common case.
    private func classifier(
        valid: [String: Set<String>],
        functional: Set<String>? = nil,
        enabled: [String] = ["en", "he"],
        corrections: [String: String] = [:],
        convert: @escaping (String) -> String?
    ) -> WrongLayoutClassifier {
        WrongLayoutClassifier(
            spellChecker: FakeSpellChecker(valid: valid, functional: functional,
                                           corrections: corrections),
            candidates: { word in convert(word).map { [($0, "target")] } ?? [] },
            enabledLanguages: { enabled })
    }

    // MARK: - The two-sided core

    func testMisspelledSourceButValidSwap_isWrongLayout() {
        let c = classifier(valid: ["he": ["היהי"], "en": []], convert: { $0 == "susu" ? "היהי" : nil })
        XCTAssertTrue(c.isWrongLayout("susu"))
    }

    func testSuggestionReturnsSwappedWordWhenWrongLayout() {
        let c = classifier(valid: ["he": ["שלום"], "en": []], convert: { $0 == "akuo" ? "שלום" : nil })
        XCTAssertEqual(c.wrongLayoutSuggestion("akuo"), "שלום")
    }

    func testValidSourceWord_isNotWrongLayout() {
        let c = classifier(valid: ["en": ["hello"]],
                           convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertFalse(c.isWrongLayout("hello"))
    }

    func testMisspelledSourceAndMisspelledSwap_isNotWrongLayout() {
        let c = classifier(valid: ["en": [], "he": []], convert: { $0 == "xqz" ? "לם" : nil })
        XCTAssertFalse(c.isWrongLayout("xqz"))
    }

    // MARK: - Verdicts (the diagnostics trail runs on these)

    func testVerdictDistinguishesNearMissFromIntentionalWord() {
        // A near-miss (source flagged, no candidate validates) is the key
        // false-negative signal for beta reports; it must not be conflated with
        // "the word looked intentional".
        let c = classifier(valid: ["en": [], "he": []], convert: { $0 == "xqz" ? "לם" : nil })
        XCTAssertEqual(c.verdict("xqz"), .slipWithoutValidSwap)

        let c2 = classifier(valid: ["en": ["hello"], "he": []],
                            convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertEqual(c2.verdict("hello"), .notSlip)
    }

    func testVerdictIneligibleForNonWords() {
        let c = classifier(valid: [:], convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertEqual(c.verdict("ab12"), .ineligible)
        XCTAssertEqual(c.verdict(""), .ineligible)
    }

    func testMatchSignalReportsWhyItBelieved() {
        // Misspelled source → .misspelled
        let m1 = classifier(valid: ["he": ["שלום"], "en": []], convert: { $0 == "akuo" ? "שלום" : nil })
            .wrongLayoutMatch("akuo")
        XCTAssertEqual(m1?.signal, .misspelled)

        // Valid Hebrew with an illegitimate geresh → .tell
        let m2 = classifier(valid: ["he": ["ים'"], "en": ["how"]], convert: { $0 == "ים'" ? "how" : nil })
            .wrongLayoutMatch("ים'")
        XCTAssertEqual(m2?.signal, .tell)

        // Lone letter → .single
        let m3 = classifier(valid: [:], functional: [], convert: { $0 == "ן" ? "i" : nil })
            .wrongLayoutMatch("ן")
        XCTAssertEqual(m3?.signal, .single)
    }

    func testNoConversion_isNotWrongLayout() {
        let c = classifier(valid: ["en": [], "he": []], convert: { _ in nil })
        XCTAssertFalse(c.isWrongLayout("susu"))
    }

    func testEmptyConversionRejected() {
        let c = classifier(valid: ["en": [], "he": []], convert: { _ in "" })
        XCTAssertFalse(c.isWrongLayout("susu"))
    }

    // MARK: - Noise guards

    func testEmptyStringRejected() {
        let c = classifier(valid: [:], convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertFalse(c.isWrongLayout(""))
    }

    func testDigitsRejected() {
        let c = classifier(valid: [:], convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertFalse(c.isWrongLayout("ab12"))
    }

    func testAllPunctuationRejected() {
        let c = classifier(valid: [:], convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertFalse(c.isWrongLayout("!!!"))
    }

    // MARK: - Language selection by script

    func testHebrewScriptCheckedAgainstHebrew() {
        let c = classifier(valid: ["en": ["hello"], "he": []], convert: { $0 == "יקרק" ? "hello" : nil })
        XCTAssertTrue(c.isWrongLayout("יקרק"))
    }

    // MARK: - Structural tells (OrthographyRules)

    func testIllegitimateGereshFlagsEvenWhenSourceIsValidHebrew() {
        // "ים'" spells a real Hebrew word per the checker, but a ' after ם is not
        // a legitimate geresh; the swap "how" confirms English on the Hebrew layout.
        let c = classifier(valid: ["he": ["ים'"], "en": ["how"]], convert: { $0 == "ים'" ? "how" : nil })
        XCTAssertEqual(c.wrongLayoutSuggestion("ים'"), "how")
    }

    func testLegitimateGereshStaysHebrew() {
        let c = classifier(valid: ["he": ["ג'ז"], "en": []],
                           convert: { _ in XCTFail("should not convert"); return nil })
        XCTAssertFalse(c.isWrongLayout("ג'ז"))
    }

    func testIllegitimateGereshStillRequiresValidSwap() {
        let c = classifier(valid: ["he": ["ים'"], "en": []], convert: { $0 == "ים'" ? "hoq" : nil })
        XCTAssertFalse(c.isWrongLayout("ים'"))
    }

    func testTellQualifiesSourceWhenNoDictionaryWorks() {
        // Greek has no working dictionary on a stock machine, but "quick" typed on
        // the Greek layout embeds the q-key erotimatiko: the tell qualifies the
        // source, and the English dictionary validates the swap.
        let c = classifier(valid: ["en": ["quick"]], functional: ["en"], enabled: ["en", "el"],
                           convert: { $0 == ";θιψκ" ? "quick" : nil })
        XCTAssertTrue(c.isWrongLayout(";θιψκ"))
    }

    // MARK: - Dictionary trust

    func testNonFunctionalTargetDictionaryNeverValidates() {
        // The Greek "dictionary" exists in name only (flags nothing). A misspelled
        // Latin word must NOT fire toward it: an un-checkable "valid" is not valid.
        let c = classifier(valid: ["en": []], functional: ["en"], enabled: ["en", "el"],
                           convert: { $0 == "xqzuu" ? "χπζθθ" : nil })
        XCTAssertFalse(c.isWrongLayout("xqzuu"))
    }

    func testNoFunctionalSourceDictionaryAndNoTell_isNotSlip() {
        // Cyrillic word, no working Cyrillic dictionary, no structural tell:
        // nothing can establish it as wrong, so it must be left alone.
        let c = classifier(valid: ["en": ["hello"]], functional: ["en"], enabled: ["en", "ru"],
                           convert: { _ in "hello" })
        XCTAssertFalse(c.isWrongLayout("руддщ"))
    }

    func testSourceValidInAnyOfItsLanguagesIsNotSlip() {
        // With Russian AND Ukrainian layouts enabled, a word valid in either
        // language was plausibly intentional; only misspelled-in-both is a slip.
        let c = classifier(valid: ["ru": [], "uk": ["привіт"], "en": ["hello"]],
                           enabled: ["en", "ru", "uk"],
                           convert: { $0 == "привіт" ? "hello" : nil })
        XCTAssertFalse(c.isWrongLayout("привіт"))
    }

    // MARK: - Language set is the enabled layouts, not the whole system list

    func testSlipStandsEvenIfALenientNonLayoutLanguageWouldAcceptIt() {
        // "nv" (מה typed on Hebrew) is a real word in Spanish/Dutch. With only the
        // user's ENABLED layouts (en, he) judging, it is misspelled-everywhere and
        // fires. This pins the regression: unioning macOS's full preferred-language
        // list (which includes es/nl) made "nv" look intentional and killed the
        // "nv vnmc" → "מה המצב" conversion.
        let c = classifier(valid: ["en": [], "he": ["מה"]], enabled: ["en", "he"],
                           convert: { $0 == "nv" ? "מה" : nil })
        XCTAssertTrue(c.isWrongLayout("nv"))

        // Demonstrate the hazard: hand the classifier the broad language set and the
        // same word is judged "valid somewhere" and no longer a slip.
        let broad = classifier(valid: ["en": [], "he": ["מה"], "es": ["nv"]],
                               enabled: ["en", "he", "es"],
                               convert: { $0 == "nv" ? "מה" : nil })
        XCTAssertFalse(broad.isWrongLayout("nv"))
    }

    // MARK: - Multiple candidate layouts

    func testPicksTheCandidateLayoutThatValidates() {
        // Three layouts enabled: the Russian candidate validates, the Hebrew one
        // is junk; the match must carry the validating layout's ID.
        let checker = FakeSpellChecker(valid: ["ru": ["привет"], "en": [], "he": []])
        let c = WrongLayoutClassifier(
            spellChecker: checker,
            candidates: { word in
                word == "ghbdtn" ? [("עיכגאמ", "HE"), ("привет", "RU")] : []
            },
            enabledLanguages: { ["en", "ru", "he"] })
        XCTAssertEqual(c.wrongLayoutMatch("ghbdtn"),
                       WrongLayoutMatch(suggestion: "привет", targetSourceID: "RU", signal: .misspelled))
    }

    func testCandidateCarryingItsOwnTellIsRejected() {
        // A candidate with a structurally impossible form can't be a real word,
        // whatever a dictionary claims.
        let c = classifier(valid: ["he": ["מםא"], "en": []], convert: { $0 == "not" ? "מםא" : nil })
        XCTAssertFalse(c.isWrongLayout("not"))
    }

    // MARK: - Apostrophe elision (informal chat spelling)

    func testSwapValidatesWhenCorrectionOnlyRestoresApostrophes() {
        // "גםמא" swaps to "dont": not in the dictionary, but its correction is
        // "don't" — the same word with the apostrophe restored. Verified live:
        // the checker corrects dont/youre/isnt but offers nothing for gibberish.
        let c = classifier(valid: ["he": [], "en": []],
                           corrections: ["dont": "don't"],
                           convert: { $0 == "גםמא" ? "dont" : nil })
        XCTAssertEqual(c.wrongLayoutSuggestion("גםמא"), "dont")
    }

    func testSwapWithUnrelatedCorrectionStaysInvalid() {
        // A correction that changes letters (not just apostrophes) is a different
        // word; the swap remains gibberish.
        let c = classifier(valid: ["he": [], "en": []],
                           corrections: ["akuo": "auk"],
                           convert: { $0 == "טםו" ? "akuo" : nil })
        XCTAssertNil(c.wrongLayoutSuggestion("טםו"))
    }

    func testSwapWithNoCorrectionStaysInvalid() {
        let c = classifier(valid: ["he": [], "en": []],
                           convert: { $0 == "xqz" ? "vnmc" : nil })
        XCTAssertNil(c.wrongLayoutSuggestion("xqz"))
    }

    func testSourceContractionIsNotAConfidentSlipEvenWithValidSwap() {
        // "hes" is flagged by the en checker, but its correction "he's" only restores an
        // apostrophe — it reads as intentional English, so it must NOT be a confident
        // wrong-layout match even though it swaps to a real Hebrew word. (Auto-switch
        // then treats it as at most ambiguous, never a fire trigger on its own.)
        let c = classifier(valid: ["he": ["יקד"], "en": []],
                           corrections: ["hes": "he's"],
                           convert: { $0 == "hes" ? "יקד" : nil })
        XCTAssertFalse(c.isWrongLayout("hes"))
        XCTAssertEqual(c.verdict("hes"), .notSlip)
    }

    // MARK: - Single letters (validated by table, not by dictionary)

    func testSingleCharSwappingToTableWordFires() {
        // "ן" swaps to "i": a real single-letter English word, no dictionary needed.
        let c = classifier(valid: [:], functional: [], convert: { $0 == "ן" ? "i" : nil })
        XCTAssertEqual(c.wrongLayoutSuggestion("ן"), "i")
    }

    func testSingleCharSwappingOutsideTheTableDoesNotFire() {
        // "e" is not a standalone English word; the table, not the checker, decides.
        let c = classifier(valid: ["en": ["e"]], convert: { $0 == "ק" ? "e" : nil })
        XCTAssertFalse(c.isWrongLayout("ק"))
    }
}
