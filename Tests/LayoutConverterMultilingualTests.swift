import XCTest

// Deterministic, machine-independent tests of the generic layout converter for
// every non-Latin script we want to support. Layouts are built from fixtures
// using the REAL key mappings (QWERTY physical positions → each script), so they
// run anywhere with no installed layouts and double as documentation of which
// gibberish maps to which word.
final class LayoutConverterMultilingualTests: XCTestCase {

    // QWERTY physical-key order; the index is used as a consistent key code.
    private static let order = Array("qwertyuiopasdfghjklzxcvbnm")

    private func makeLayout(_ id: String, _ keys: [String]) -> LayoutMap {
        precondition(keys.count == Self.order.count, "fixture must cover all 26 keys")
        var table: [UInt16: String] = [:]
        for (i, char) in keys.enumerated() { table[UInt16(i)] = char }
        return LayoutMap(sourceID: id, keyToChar: table)
    }
    private func split(_ s: String) -> [String] { s.map(String.init) }

    // Real layouts, in q-w-e-…-m order.
    private lazy var english   = makeLayout("ABC", split("qwertyuiopasdfghjklzxcvbnm"))
    private lazy var russian   = makeLayout("RU",  split("йцукенгшщзфывапролдячсмить"))
    private lazy var ukrainian = makeLayout("UA",  split("йцукенгшщзфівапролдячсмить"))
    private lazy var greek     = makeLayout("GR",  split(";ςερτυθιοπασδφγηξκλζχψωβνμ"))
    private lazy var hebrew    = makeLayout("HE",  split("/'קראטוןםפשדגכעיחלךזסבהנמצ"))
    private lazy var arabic    = makeLayout("AR",
        ["ض","ص","ث","ق","ف","غ","ع","ه","خ","ح","ش","س","ي","ب","ل","ا","ت","ن","م",
         "ئ","ء","ؤ","ر","لا","ى","ة"])

    // Assert a (gibberish ⟷ word) pair converts correctly in BOTH directions and
    // that each conversion targets the other layout.
    private func assertPair(_ foreign: LayoutMap, gibberish: String, word: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let toForeign = LayoutConverter.convert(gibberish, between: english, and: foreign, currentSourceID: nil)
        XCTAssertEqual(toForeign.converted, word, "→ \(foreign.sourceID)", file: file, line: line)
        XCTAssertEqual(toForeign.targetSourceID, foreign.sourceID, file: file, line: line)

        let toEnglish = LayoutConverter.convert(word, between: english, and: foreign, currentSourceID: nil)
        XCTAssertEqual(toEnglish.converted, gibberish, "→ ABC", file: file, line: line)
        XCTAssertEqual(toEnglish.targetSourceID, english.sourceID, file: file, line: line)
    }

    func testRussian()   { assertPair(russian,   gibberish: "ghbdtn", word: "привет") }  // privet — "hi"
    func testUkrainian() { assertPair(ukrainian, gibberish: "ghbdsn", word: "привіт") }  // pryvit — "hi"
    func testGreek()     { assertPair(greek,     gibberish: "geia",   word: "γεια") }     // geia — "hi"
    func testHebrew()    { assertPair(hebrew,    gibberish: "akuo",   word: "שלום") }     // shalom
    func testArabic()    { assertPair(arabic,    gibberish: "sghl",   word: "سلام") }     // salaam

    // A multi-word Russian phrase (with a space) round-trips intact.
    func testRussianPhraseRoundTrip() {
        let gibberish = "rfr ltkf"   // keys for "как дела" (how are you)
        let forward = LayoutConverter.convert(gibberish, between: english, and: russian, currentSourceID: nil)
        XCTAssertEqual(forward.converted, "как дела")
        let back = LayoutConverter.convert(forward.converted, between: english, and: russian, currentSourceID: nil)
        XCTAssertEqual(back.converted, gibberish)
    }

    // Direction is detected from the script, regardless of order.
    func testDirectionFollowsScript() {
        XCTAssertEqual(LayoutConverter.convert("ghbdtn", between: english, and: russian, currentSourceID: nil).targetSourceID, "RU")
        XCTAssertEqual(LayoutConverter.convert("привет", between: english, and: russian, currentSourceID: nil).targetSourceID, "ABC")
    }

    // Characters with no mapping (spaces, digits) pass through unchanged.
    func testUnmappedCharsPassThrough() {
        let r = LayoutConverter.convert("ghbdtn 123", between: english, and: russian, currentSourceID: nil)
        XCTAssertEqual(r.converted, "привет 123")
    }
}
