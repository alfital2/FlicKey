import XCTest

final class ConversionEngineTests: XCTestCase {

    // MARK: - English → Hebrew

    func testHelloConvertsToHebrew() {
        // h→י e→ק l→ך l→ך o→ם
        let (out, target) = ConversionEngine.convert("hello")
        XCTAssertEqual(out, "יקךךם")
        XCTAssertEqual(target, .he)
    }

    // MARK: - Hebrew → English roundtrip

    func testHebrewRoundtripsToEnglish() {
        let (he, _) = ConversionEngine.convert("hello")        // → "יקךךם"
        let (back, target) = ConversionEngine.convert(he)      // → "hello"
        XCTAssertEqual(back, "hello")
        XCTAssertEqual(target, .en)
    }

    func testHebrewWordToEnglish() {
        // שלום → a(ש) e is not... map by reverse: ש→a ל→k ו→u ם→o
        let (out, target) = ConversionEngine.convert("שלום")
        XCTAssertEqual(out, "akuo")
        XCTAssertEqual(target, .en)
    }

    // MARK: - Smart-quote (WhatsApp "w" bug)

    func testStraightApostropheConvertsToW() {
        // "want" typed on the Hebrew layout: w→' a→ש n→מ t→א
        let (out, _) = ConversionEngine.convert("'שמא")
        XCTAssertEqual(out, "want")
    }

    func testCurlyApostropheStillConvertsToW() {
        // Same, but the ' was smart-quoted to ’ (U+2019) — must still yield "want".
        let (out, target) = ConversionEngine.convert("\u{2019}שמא")
        XCTAssertEqual(out, "want")
        XCTAssertEqual(target, .en)
    }

    func testSmartQuotedSentence() {
        // The reported example, with both w's smart-quoted.
        let gibberish = "ךקאד דשט ן \u{2019}שמא אם \u{2019}רןאק"
        let (out, _) = ConversionEngine.convert(gibberish)
        XCTAssertEqual(out, "lets say i want to write")
    }

    // MARK: - Mixed text detection (majority wins)

    func testMixedMajorityEnglish() {
        // 2 EN vs 1 HE → English source → convert to Hebrew
        XCTAssertEqual(ConversionEngine.detectLanguage("abש"), .en)
    }

    func testMixedMajorityHebrew() {
        // 3 HE vs 2 EN → Hebrew source → convert to English
        XCTAssertEqual(ConversionEngine.detectLanguage("אבגde"), .he)
    }

    func testTieGoesToEnglish() {
        // 1 EN vs 1 HE → tie → English (enCount >= heCount)
        XCTAssertEqual(ConversionEngine.detectLanguage("aש"), .en)
    }

    // MARK: - Punctuation

    func testPunctuationMappings() {
        XCTAssertEqual(ConversionEngine.convert(",").converted, "ת")
        XCTAssertEqual(ConversionEngine.convert(".").converted, "ץ")
        XCTAssertEqual(ConversionEngine.convert("/").converted, ".")
        XCTAssertEqual(ConversionEngine.convert("'").converted, ",")
    }

    func testUnmappedCharactersPassThrough() {
        // Digits / spaces have no mapping and should pass through unchanged.
        let (out, _) = ConversionEngine.convert("a 1")
        // a→ש, space passthrough, 1 passthrough
        XCTAssertEqual(out, "ש 1")
    }

    // MARK: - Edge cases

    func testEmptyString() {
        let (out, target) = ConversionEngine.convert("")
        XCTAssertEqual(out, "")
        XCTAssertEqual(target, .he) // empty → tie → en source → he target
    }

    // MARK: - Reverse map integrity

    func testReverseMapPrefersLowercase() {
        // Every Hebrew letter maps back to its lowercase English key.
        XCTAssertEqual(ConversionEngine.heToEn["ש"], "a")
        XCTAssertEqual(ConversionEngine.heToEn["ק"], "e")
        XCTAssertEqual(ConversionEngine.heToEn["צ"], "m")
    }
}
