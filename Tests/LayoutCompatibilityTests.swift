import XCTest

// Established user-facing behavior is not identical to raw keyboard replay:
// Hebrew's Shift plane echoes Latin, but users expect uppercase mistakes fixed.
final class LayoutCompatibilityTests: XCTestCase {
    private func map(_ name: String) throws -> LayoutMap {
        try XCTUnwrap(LayoutMap(sourceID: "com.apple.keylayout." + name, includingDisabled: true))
    }

    func testAllEnglishLetterCasesRetainHebrewCorrectionBehavior() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC")
        for original in Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
            + ["AKUO", "Akuo", "aBc", "QWERTY", "hello WORLD!"] {
            let expected = ConversionEngine.convert(original).0
            let textOnly = ConversionRouter.convertText(original, maps: [en, he], currentSourceID: en.sourceID)
            XCTAssertEqual(textOnly.converted, expected, original)
            let strokes = try original.map { character -> KeyboardStroke in
                if character == " " { return KeyboardStroke(keyCode: 49) }
                let key = try XCTUnwrap(en.key(forCharacter: String(character)))
                return KeyboardStroke(keyCode: key.key, shift: key.shift)
            }
            let captured = ConversionRouter.convertText(original, maps: [en, he], currentSourceID: en.sourceID,
                                                         physicalStrokes: strokes)
            XCTAssertEqual(captured.converted, expected, "captured \(original)")
            XCTAssertEqual(captured.sourceID, he.sourceID)
        }
    }

    func testCapsLockStillCorrectsToHebrewAndCyclesBack() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC")
        let strokes = [UInt16(0), 40, 32, 31].map { KeyboardStroke(keyCode: $0, capsLock: true) }
        XCTAssertEqual(en.transducer.render(strokes), "AKUO")
        let result = ConversionRouter.convertText("AKUO", maps: [en, he], currentSourceID: en.sourceID,
                                                  physicalStrokes: strokes)
        XCTAssertEqual(result.converted, "שלום")
        let back = ConversionRouter.convertText(result.converted, maps: [en, he], currentSourceID: he.sourceID)
        XCTAssertEqual(back.converted, "akuo")
    }

    func testArabicCapturedShiftStillProducesItsDistinctLetter() throws {
        let en = try map("ABC"), ar = try map("ArabicPC")
        let result = ConversionRouter.convertText("H", maps: [en, ar], currentSourceID: en.sourceID,
                                                  physicalStrokes: [KeyboardStroke(keyCode: 4, shift: true)])
        XCTAssertEqual(result.converted, "أ", "Hebrew compatibility must not discard Arabic Shift intent")
    }

    func testCapturedCyrillicCapitalDoesNotLeakLatinIntoHebrew() throws {
        let ru = try map("Russian"), he = try map("Hebrew-PC")
        let result = ConversionRouter.convertText("Ф", maps: [ru, he], currentSourceID: ru.sourceID,
                                                  physicalStrokes: [KeyboardStroke(keyCode: 0, shift: true)])
        XCTAssertEqual(result.converted, "ש")
    }

    func testOrdinaryPunctuationNeverChoosesAnUnassignedJISKey() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC"), ru = try map("Russian")
        for (source, input) in [(he, "_"), (ru, "*")] {
            let result = LayoutConverter.convert(input, between: source, and: en, currentSourceID: source.sourceID)
            XCTAssertEqual(result.converted, input)
            XCTAssertEqual(LayoutConverter.parses(of: input, from: source, to: en).first, input)
        }
        XCTAssertEqual(ConversionRouter.convertText("_", maps: [he, en], currentSourceID: he.sourceID).converted, "_")
    }

    func testAnUnassignedTargetPlaneDoesNotDeleteTheInput() throws {
        let en = try map("ABC"), ge = try map("Georgian-QWERTY")
        let strokes = [KeyboardStroke(keyCode: 4, shift: true)]
        let result = ConversionRouter.convertText("H", maps: [en, ge], currentSourceID: en.sourceID,
                                                  physicalStrokes: strokes)
        XCTAssertFalse(result.converted.isEmpty)
        XCTAssertEqual(result.converted, "ჰ".uppercased())
    }

    func testCurrencyAndTypographyRemainIntactWithAndWithoutKeyHistory() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC"), ru = try map("Russian")
        for (source, target) in [(en, he), (he, en), (en, ru), (ru, en)] {
            let text = "€ £ © ™ … —"
            XCTAssertEqual(LayoutConverter.convert(text, between: source, and: target,
                                                    currentSourceID: source.sourceID).converted, text)
        }
        let strokes = [KeyboardStroke(keyCode: 19, shift: true, option: true)]
        XCTAssertEqual(en.transducer.render(strokes), "€")
        let result = ConversionRouter.convertText("€", maps: [en, he], currentSourceID: en.sourceID,
                                                  physicalStrokes: strokes)
        XCTAssertEqual(result.converted, "€")
    }

    func testUnambiguousManualConversionDoesNotConsultDictionary() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC")
        var lookups = 0
        let result = ConversionRouter.convertText("akuo akuo", maps: [en, he], currentSourceID: en.sourceID,
                                                  preferring: { _ in lookups += 1; return false })
        XCTAssertEqual(result.converted, "שלום שלום")
        XCTAssertEqual(lookups, 0, "ordinary manual fixes must not wait on the spell-check service")
    }

    func testCapturedDeadAccentIsNotMistakenForCurrency() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC")
        let strokes = [KeyboardStroke(keyCode: 14, option: true), KeyboardStroke(keyCode: 14)]
        let wrong = try XCTUnwrap(he.transducer.render(strokes))
        XCTAssertEqual(en.transducer.render(strokes), "é")
        let result = ConversionRouter.convertText(wrong, maps: [he, en], currentSourceID: he.sourceID,
                                                  physicalStrokes: strokes)
        XCTAssertEqual(result.converted, "é")
    }
}
