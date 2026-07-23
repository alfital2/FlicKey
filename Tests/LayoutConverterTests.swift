import XCTest

// Validates the generic (UCKeyTranslate-derived) converter against the known
// Hebrew/English mapping. Skips on machines without those two layouts enabled.
final class LayoutConverterTests: XCTestCase {

    private func requireHebrewEnglish() throws {
        let firstTwo = Set(InputSourceCatalog.enabledSources().map { $0.id }.prefix(2))
        guard firstTwo == ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew-PC"] else {
            throw XCTSkip("Needs ABC + Hebrew-PC as the two enabled layouts")
        }
    }

    func testEnglishToHebrew() throws {
        try requireHebrewEnglish()
        XCTAssertEqual(LayoutConverter.convert("abc")?.converted, "שנב")
    }

    // Regression: UPPERCASE / mixed-case English must still convert to Hebrew
    // (Hebrew has no case, so it maps to the same letters as lowercase).
    // All-caps text is direction-ambiguous (the real Hebrew layout echoes Latin
    // capitals on Shift), so the tie is broken by the current input source —
    // pin it to ABC (the user typed caps on the English layout) instead of
    // inheriting whatever layout the test machine happens to be in.
    func testUppercaseEnglishConverts() throws {
        try requireHebrewEnglish()
        let abc = "com.apple.keylayout.ABC"
        XCTAssertEqual(LayoutConverter.convert("AKUO", currentSourceID: abc)?.converted, "שלום")
        XCTAssertEqual(LayoutConverter.convert("AKUO", currentSourceID: abc)?.converted,
                       LayoutConverter.convert("akuo", currentSourceID: abc)?.converted)
        // No Latin letter may survive a mixed-case conversion.
        let mixed = LayoutConverter.convert("Shalom", currentSourceID: abc)?.converted ?? ""
        XCTAssertFalse(mixed.contains { $0.isASCII && $0.isLetter },
                       "a Latin letter passed through: \(mixed)")
    }

    func testHebrewToEnglish() throws {
        try requireHebrewEnglish()
        XCTAssertEqual(LayoutConverter.convert("שנב")?.converted, "abc")
    }

    func testGaragePhrase() throws {
        try requireHebrewEnglish()
        XCTAssertEqual(LayoutConverter.convert("dtrtdw")?.converted, "גאראג'")
    }

    func testTargetIsTheOtherLayout() throws {
        try requireHebrewEnglish()
        XCTAssertEqual(LayoutConverter.convert("abc")?.targetSourceID ?? nil, "com.apple.keylayout.Hebrew-PC")
        XCTAssertEqual(LayoutConverter.convert("שנב")?.targetSourceID ?? nil, "com.apple.keylayout.ABC")
    }

    func testRoundTripWithLetters() throws {
        try requireHebrewEnglish()
        // A word with a trailing geresh round-trips because its letters set the
        // direction unambiguously in both passes.
        let toHebrew = LayoutConverter.convert("dtrtdw")
        XCTAssertEqual(toHebrew?.converted, "גאראג'")
        let back = LayoutConverter.convert(toHebrew!.converted)
        XCTAssertEqual(back?.converted, "dtrtdw")
    }

    // Regression: w → ' → w. The geresh has no letters, so direction comes from
    // the current input source (which each conversion flips).
    func testGereshRoundTripsViaCurrentLayout() throws {
        try requireHebrewEnglish()
        let abc = "com.apple.keylayout.ABC"
        let hebrew = "com.apple.keylayout.Hebrew-PC"

        // Typed 'w' in English → geresh, and we switch to Hebrew.
        let forward = LayoutConverter.convert("w", currentSourceID: abc)
        XCTAssertEqual(forward?.converted, "'")
        XCTAssertEqual(forward?.targetSourceID ?? nil, hebrew)

        // Now in Hebrew, the geresh converts back to 'w'.
        let back = LayoutConverter.convert("'", currentSourceID: hebrew)
        XCTAssertEqual(back?.converted, "w")
        XCTAssertEqual(back?.targetSourceID ?? nil, abc)
    }

    // Regression: repeated presses toggle w ↔ ' — they must never cascade to , or ת.
    func testPunctuationTogglesAndNeverCascades() throws {
        try requireHebrewEnglish()
        let abc = "com.apple.keylayout.ABC"

        var text = "w"
        var current: String? = abc
        var sequence: [String] = []
        for _ in 0..<4 {
            guard let result = LayoutConverter.convert(text, currentSourceID: current) else {
                return XCTFail("no conversion")
            }
            text = result.converted
            current = result.targetSourceID ?? current
            sequence.append(text)
        }
        // Strictly toggles between ' and w; never reaches , or ת.
        XCTAssertEqual(sequence, ["'", "w", "'", "w"])
    }
}
