import Carbon
import XCTest

final class LayoutRecoveryTests: XCTestCase {
    private static var nativeMaps: [String: LayoutMap] = [:]
    private func map(_ name: String) throws -> LayoutMap {
        if let cached = Self.nativeMaps[name] { return cached }
        let result = try XCTUnwrap(LayoutMap(sourceID: "com.apple.keylayout." + name, includingDisabled: true))
        Self.nativeMaps[name] = result
        return result
    }
    private func convert(_ text: String, _ source: String, _ target: String) throws -> String {
        let a = try map(source), b = try map(target)
        return LayoutConverter.convert(text, between: a, and: b, currentSourceID: a.sourceID).converted
    }

    func testArabicWordCanMixLigatureAndSeparateLetterReadings() throws {
        let ar = try map("ArabicPC"), en = try map("ABC")
        XCTAssertTrue(LayoutConverter.parses(of: "لاقهلاف", from: ar, to: en).contains("bright"))
        let result = LayoutConverter.convert("لاقهلاف", toSourceID: en.sourceID,
            maps: [ar, en], currentSourceID: ar.sourceID, preferring: { $0 == "bright" })
        XCTAssertEqual(result?.converted, "bright")
    }

    func testArabicPhraseResolvesEachWordAndPreservesWhitespace() throws {
        let ar = try map("ArabicPC"), en = try map("ABC")
        let result = LayoutConverter.convert("لاشي\tىهلاف\nلاقهلاف  ", toSourceID: en.sourceID,
            maps: [ar, en], currentSourceID: ar.sourceID,
            preferring: { ["bad", "night", "bright"].contains($0) })
        XCTAssertEqual(result?.converted, "bad\tnight\nbright  ")
    }

    func testGreekAndSpanishDeadKeyCompositionInBothDirections() throws {
        XCTAssertEqual(try convert("kalhm;era", "ABC", "Greek"), "καλημέρα")
        XCTAssertEqual(try convert("καλημέρα", "Greek", "ABC"), "kalhm;era")
        XCTAssertEqual(try convert("buenos d'ias", "ABC", "Spanish-ISO"), "buenos días")
        XCTAssertEqual(try convert("buenos días", "Spanish-ISO", "ABC"), "buenos d'ias")
    }

    func testThaiCombiningMarksAreRecoverableInsideGraphemes() throws {
        XCTAssertEqual(try convert("้ำสสน ไนพสก", "Thai", "ABC"), "hello world")
    }

    func testHindiViramaAndCombiningVowels() throws {
        XCTAssertEqual(try convert("vcmdls", "ABC", "Devanagari"), "नमस्ते")
        XCTAssertEqual(try convert("नमस्ते", "Devanagari", "ABC"), "vcmdls")
        XCTAssertEqual(try convert("पाततद", "Devanagari", "ABC"), "hello")
    }

    func testRussianCapitalsKeepShiftOnPunctuationKeys() throws {
        XCTAssertEqual(try convert("ЖЭХЪБЮЁ", "Russian", "ABC"), ":\"{}<>|")
    }

    func testCanonicalUnicodeAndUnmappedText() throws {
        XCTAssertEqual(try convert("καλημέρα".decomposedStringWithCanonicalMapping, "Greek", "ABC"), "kalhm;era")
        XCTAssertEqual(try convert("hello 👩🏽‍💻\n\t", "ABC", "Russian"), "руддщ 👩🏽‍💻\n\t")
    }

    func testCapturedKeysResolveArabicAndArmenianWithoutDictionary() throws {
        let en = try map("ABC")
        for (name, strokes, expected) in [
            ("ArabicPC", [KeyboardStroke(keyCode: 11)], "b"),
            ("ArabicPC", [KeyboardStroke(keyCode: 5), KeyboardStroke(keyCode: 4)], "gh"),
            ("Armenian-HMQWERTY", [KeyboardStroke(keyCode: 32)], "u"),
            ("Armenian-HMQWERTY", [KeyboardStroke(keyCode: 13)], "w"),
        ] {
            let source = try map(name)
            let text = try XCTUnwrap(source.transducer.render(strokes))
            XCTAssertEqual(LayoutConverter.convertCaptured(text, strokes: strokes, from: source, to: en), expected)
        }
    }

    func testCapturedShiftAndCapsLockRemainDifferent() throws {
        let en = try map("ABC"), ar = try map("ArabicPC")
        let shift = [KeyboardStroke(keyCode: 4, shift: true)]
        let caps = [KeyboardStroke(keyCode: 4, capsLock: true)]
        XCTAssertEqual(en.transducer.render(shift), "H")
        XCTAssertEqual(en.transducer.render(caps), "H")
        XCTAssertEqual(LayoutConverter.convertCaptured("H", strokes: shift, from: en, to: ar), "أ")
        XCTAssertNotEqual(ar.transducer.render(shift), ar.transducer.render(caps))
    }

    func testUnverifiedKeyHistoryCannotOverrideText() throws {
        let en = try map("ABC"), ar = try map("ArabicPC")
        let strokes = [KeyboardStroke(keyCode: 11)]
        XCTAssertNil(LayoutConverter.convertCaptured("hello", strokes: strokes, from: en, to: ar))
        var trace = LayoutTypingTrace()
        trace.append(strokes[0], sourceID: en.sourceID)
        XCTAssertEqual(trace.verified(for: "b", map: en), strokes)
        XCTAssertNil(trace.verified(for: "a", map: en))
        XCTAssertNil(trace.verified(for: "لا", map: ar))
        trace.reset()
        XCTAssertNil(trace.verified(for: "b", map: en))
    }

    func testTraceSuffixAndLengthLimit() throws {
        let en = try map("ABC")
        var trace = LayoutTypingTrace()
        for key: UInt16 in [0, 49, 11] { trace.append(KeyboardStroke(keyCode: key), sourceID: en.sourceID) }
        trace.keepSuffix("b", map: en)
        XCTAssertEqual(trace.verified(for: "b", map: en), [KeyboardStroke(keyCode: 11)])
        for _ in 0..<500 { trace.append(KeyboardStroke(keyCode: 0), sourceID: en.sourceID) }
        XCTAssertLessThanOrEqual(trace.strokes.count, 256)
        XCTAssertNil(trace.verified(for: String(repeating: "a", count: 500), map: en))
    }

    func testUnsupportedIMEAndSingleLayoutLeaveTextUntouched() throws {
        let en = try map("ABC"), he = try map("Hebrew-PC")
        let ime = ConversionRouter.convertText("hello 日本語", maps: [en, he],
            currentSourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping")
        XCTAssertEqual(ime.converted, "hello 日本語")
        XCTAssertNil(ime.sourceID)
        let single = ConversionRouter.convertText("hello", maps: [en], currentSourceID: en.sourceID)
        XCTAssertEqual(single.converted, "hello")
        XCTAssertNil(single.sourceID)
    }

    func testManualRouterPrefersVerifiedKeysThenDictionary() throws {
        let en = try map("ABC"), ar = try map("ArabicPC")
        let exact = ConversionRouter.convertText("لا", maps: [ar, en], currentSourceID: ar.sourceID,
            physicalStrokes: [KeyboardStroke(keyCode: 11)])
        XCTAssertEqual(exact.converted, "b")
        let reconstructed = ConversionRouter.convertText("لاقهلاف", maps: [ar, en], currentSourceID: ar.sourceID,
            preferring: { $0 == "bright" })
        XCTAssertEqual(reconstructed.converted, "bright")
    }

    func testSourceScoreTieUsesCurrentLayout() {
        let a = LayoutMap(sourceID: "a", keyToChar: [0: "a", 1: "b"])
        let b = LayoutMap(sourceID: "b", keyToChar: [0: "α", 1: "β"])
        XCTAssertEqual(LayoutConverter.convert("aα", maps: [a, b], currentSourceID: "a")?.targetSourceID, "b")
        XCTAssertEqual(LayoutConverter.convert("aα", maps: [a, b], currentSourceID: "b")?.targetSourceID, "a")
    }

    func testCandidateSearchIsBoundedForAmbiguousInput() throws {
        let ar = try map("ArabicPC"), en = try map("ABC")
        let candidates = LayoutConverter.parses(of: String(repeating: "لا", count: 20), from: ar, to: en)
        XCTAssertLessThanOrEqual(candidates.count, 64)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(LayoutConverter.parses(of: String(repeating: "لا", count: 20),
                                             from: ar, to: en, requireComplete: true).isEmpty,
                      "a truncated candidate search must never authorize an automatic rewrite")
    }

    // Independent oracle: direct UCKeyTranslate, not LayoutMap/transducer.
    private func oracle(_ strokes: [KeyboardStroke], layout: String) throws -> String {
        let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        let source = try XCTUnwrap(sources.first {
            InputSourceCatalog.string($0, kTISPropertyInputSourceID) == "com.apple.keylayout." + layout
        })
        let pointer = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes in
            let keyboard = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            var state: UInt32 = 0, result = ""
            for stroke in strokes {
                var chars = [UniChar](repeating: 0, count: 32), length = 0
                let modifiers: UInt32 = (stroke.shift ? 2 : 0) | (stroke.capsLock ? 4 : 0) | (stroke.option ? 8 : 0)
                let status = UCKeyTranslate(keyboard, stroke.keyCode, UInt16(kUCKeyActionDown), modifiers,
                    UInt32(LMGetKbdType()), 0, &state, chars.count, &length, &chars)
                XCTAssertEqual(status, noErr)
                result += String(utf16CodeUnits: chars, count: length)
            }
            return result
        }
    }

    func testCartesianCapturedRecoveryAcrossSixteenNativeLayouts() throws {
        let names = ["ABC", "Russian", "Ukrainian-PC", "Bulgarian", "Greek", "Hebrew-PC", "ArabicPC",
            "Persian-ISIRI2901", "French", "German", "Spanish-ISO", "Turkish-QWERTY-PC", "Thai",
            "Devanagari", "Armenian-HMQWERTY", "Georgian-QWERTY"]
        let keys: [UInt16] = [11, 15, 34, 5, 4, 17, 49, 0, 41, 14, 39, 34, 49]
        let samples = [
            keys.map { KeyboardStroke(keyCode: $0) },
            keys.map { KeyboardStroke(keyCode: $0, shift: $0 != 49) },
            keys.map { KeyboardStroke(keyCode: $0, capsLock: true) },
            keys.map { KeyboardStroke(keyCode: $0, option: $0 == 14) },
        ]
        let layouts = try names.map(map)
        for sample in samples {
            let texts = try names.map { try oracle(sample, layout: $0) }
            for source in layouts.indices {
                for target in layouts.indices where target != source {
                    XCTAssertEqual(LayoutConverter.convertCaptured(texts[source], strokes: sample,
                        from: layouts[source], to: layouts[target]), texts[target], "\(names[source]) → \(names[target])")
                }
            }
        }
    }
}
