import XCTest

final class WordScriptTests: XCTestCase {

    func testScriptDetection() {
        XCTAssertEqual(WordScript.script(for: "hello"), .latin)
        XCTAssertEqual(WordScript.script(for: "שלום"), .hebrew)
        XCTAssertEqual(WordScript.script(for: "привет"), .cyrillic)
        XCTAssertEqual(WordScript.script(for: "їжа"), .cyrillic)
        XCTAssertEqual(WordScript.script(for: "γεια"), .greek)
        XCTAssertEqual(WordScript.script(for: "مرحبا"), .arabic)
        // Any non-Latin scalar decides, even in a mixed word.
        XCTAssertEqual(WordScript.script(for: "abcשלום"), .hebrew)
        XCTAssertEqual(WordScript.script(for: ";θιψκ"), .greek)
    }

    func testLanguageCodeScript() {
        XCTAssertEqual(WordScript.script(forLanguage: "en"), .latin)
        XCTAssertEqual(WordScript.script(forLanguage: "fr"), .latin)
        XCTAssertEqual(WordScript.script(forLanguage: "he"), .hebrew)
        XCTAssertEqual(WordScript.script(forLanguage: "ru"), .cyrillic)
        XCTAssertEqual(WordScript.script(forLanguage: "uk"), .cyrillic)
        XCTAssertEqual(WordScript.script(forLanguage: "el"), .greek)
        XCTAssertEqual(WordScript.script(forLanguage: "ar"), .arabic)
        XCTAssertEqual(WordScript.script(forLanguage: "pt_BR"), .latin)   // region tag stripped
    }

    func testSpellLanguagesPreferEnabledLayoutsOfTheSameScript() {
        // A Cyrillic word on a machine with Russian and Ukrainian layouts is a
        // candidate in both languages; Latin layouts don't leak in.
        XCTAssertEqual(
            WordScript.spellLanguages(for: "привет", enabledLanguages: ["en", "ru", "uk"]),
            ["ru", "uk"])
        XCTAssertEqual(
            WordScript.spellLanguages(for: "hello", enabledLanguages: ["en", "ru"]),
            ["en"])
    }

    func testSpellLanguagesEmptyWhenNoEnabledLayoutMatchesTheScript() {
        // We only judge words in scripts the user actually types (their enabled
        // layouts). A Greek word with no Greek layout enabled is ignored, not
        // checked against a bundled dictionary the user never asked for.
        XCTAssertEqual(WordScript.spellLanguages(for: "γεια", enabledLanguages: ["en", "he"]), [])
        XCTAssertEqual(WordScript.spellLanguages(for: "مرحبا", enabledLanguages: []), [])
        XCTAssertEqual(WordScript.spellLanguages(for: "hello", enabledLanguages: []), [])
    }

    func testSpellLanguagesDeduplicate() {
        // A layout family can repeat a language code (e.g. two Hebrew variants).
        XCTAssertEqual(WordScript.spellLanguages(for: "שלום", enabledLanguages: ["he", "he", "en"]), ["he"])
    }

    func testSingleLetterWords() {
        XCTAssertEqual(WordScript.singleLetterWords(forLanguage: "en"), ["i", "a"])
        XCTAssertTrue(WordScript.singleLetterWords(forLanguage: "ru").contains("и"))
        XCTAssertTrue(WordScript.singleLetterWords(forLanguage: "uk").contains("і"))
        XCTAssertTrue(WordScript.singleLetterWords(forLanguage: "el").contains("ο"))
        // Hebrew and Arabic single letters attach as prefixes, never stand alone.
        XCTAssertTrue(WordScript.singleLetterWords(forLanguage: "he").isEmpty)
        XCTAssertTrue(WordScript.singleLetterWords(forLanguage: "ar").isEmpty)
    }

    func testPrimaryLanguagesTakeOneCodePerLayout() {
        // Apple's ABC layout advertises ~97 Latin languages; feeding them all into
        // detection lets any lenient dictionary (Dutch accepts "nv") veto a real
        // slip. Only each layout's primary language represents what the user types.
        let sources = [
            InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC",
                            languageCodes: ["en", "af", "nl", "es", "fr"]),
            InputSourceInfo(id: "com.apple.keylayout.Hebrew-PC", localizedName: "Hebrew – PC",
                            languageCodes: ["he", "yi"]),
        ]
        XCTAssertEqual(WordScript.primaryLanguages(of: sources), ["en", "he"])
    }

}
