import XCTest

final class KeyboardTransducerTests: XCTestCase {
    private let latin = LayoutMap(sourceID: "ABC", keyToChar: [
        11: "b", 5: "g", 4: "h", 0: "a", 2: "d", 34: "i", 17: "t",
    ])
    private let arabic = LayoutMap(sourceID: "AR", keyToChar: [
        11: "لا", 5: "ل", 4: "ا", 0: "ش", 2: "ي", 34: "ه", 17: "ف",
    ])

    func testPhysicalEvidenceDistinguishesOneDigraphKeyFromTwoKeys() {
        XCTAssertEqual(LayoutConverter.convertCaptured("لا", strokes: [KeyboardStroke(keyCode: 11)],
            from: arabic, to: latin), "b")
        XCTAssertEqual(LayoutConverter.convertCaptured("لا",
            strokes: [KeyboardStroke(keyCode: 5), KeyboardStroke(keyCode: 4)],
            from: arabic, to: latin), "gh")
        XCTAssertNil(LayoutConverter.convertCaptured("لاش", strokes: [KeyboardStroke(keyCode: 11)],
            from: arabic, to: latin), "Stale physical evidence must not replace newer text")
    }

    func testMixedAmbiguousReadingsKeepWordBoundariesAndWhitespace() throws {
        // Use a directly rendered fixture so the source cannot drift from keys.
        let source = try XCTUnwrap(arabic.transducer.render([11, 0, 2, 49, 49, 34, 5, 4, 17, 49]
            .map { KeyboardStroke(keyCode: $0) }))
        let converted = LayoutConverter.convert(source, toSourceID: "ABC",
            maps: [arabic, latin], currentSourceID: "AR",
            preferring: { ["bad", "ight"].contains($0) })
        XCTAssertEqual(converted?.converted, "bad  ight ")
    }

    func testABCDeadKeyCompositionUsesMacOSRules() throws {
        let abc = try XCTUnwrap(LayoutMap.forSource("com.apple.keylayout.ABC"))
        XCTAssertEqual(abc.transducer.render([
            KeyboardStroke(keyCode: 14, option: true), KeyboardStroke(keyCode: 14),
        ]), "é")
    }

    func testUnsupportedInputMethodLeavesManualConversionUntouched() {
        let result = ConversionRouter.convertText("akuo", maps: [latin, arabic],
                                                   currentSourceID: "an-IME")
        XCTAssertEqual(result.converted, "akuo")
        XCTAssertNil(result.sourceID)
    }
}
