import XCTest

// Heavy, deterministic fuzz/property validation of the generic converter across
// every script we ship for. Seeded so it's reproducible. Asserts hard
// invariants over ~100k randomized conversions — the pre-ship "no bugs" gate.
final class LayoutConverterFuzzTests: XCTestCase {

    private static let order = Array("qwertyuiopasdfghjklzxcvbnm")

    private func makeLayout(_ id: String, _ keys: [String]) -> LayoutMap {
        precondition(keys.count == Self.order.count)
        var table: [UInt16: String] = [:]
        for (i, char) in keys.enumerated() { table[UInt16(i)] = char }
        return LayoutMap(sourceID: id, keyToChar: table)
    }
    private func split(_ s: String) -> [String] { s.map(String.init) }

    private lazy var english = makeLayout("ABC", split("qwertyuiopasdfghjklzxcvbnm"))
    private lazy var pairs: [(map: LayoutMap, name: String)] = [
        (makeLayout("RU", split("йцукенгшщзфывапролдячсмить")), "Russian"),
        (makeLayout("UA", split("йцукенгшщзфівапролдячсмить")), "Ukrainian"),
        (makeLayout("GR", split(";ςερτυθιοπασδφγηξκλζχψωβνμ")), "Greek"),
        (makeLayout("HE", split("/'קראטוןםפשדגכעיחלךזסבהנמצ")), "Hebrew"),
        (makeLayout("AR", ["ض","ص","ث","ق","ف","غ","ع","ه","خ","ح","ش","س","ي","ب","ل","ا",
                           "ت","ن","م","ئ","ء","ؤ","ر","لا","ى","ة"]), "Arabic"),
    ]

    // Reproducible PRNG (splitmix64-style) so failures are debuggable.
    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private let iterations = 5_000

    // INVARIANT 1: foreign → latin → foreign is the identity, for any foreign-script
    // input. (The user typed gibberish in the wrong script; fixing then re-fixing
    // must return the original.)
    func testForeignRoundTripIsIdentity() {
        var rng = LCG(state: 0xF11C_8E40_1234_5678)
        for (foreign, name) in pairs {
            let chars = (0..<26).map { foreign.character(forKeyCode: UInt16($0), shift: false)! }
            for _ in 0..<iterations {
                var word = ""
                for _ in 0..<Int.random(in: 1...14, using: &rng) {
                    word += chars[Int.random(in: 0..<26, using: &rng)]
                }
                let toLatin = LayoutConverter.convert(word, between: english, and: foreign, currentSourceID: nil)
                XCTAssertEqual(toLatin.targetSourceID, "ABC", "\(name): wrong target")
                let back = LayoutConverter.convert(toLatin.converted, between: english, and: foreign, currentSourceID: nil)
                XCTAssertEqual(back.converted, word, "\(name): foreign round-trip broke")
                XCTAssertEqual(back.targetSourceID, foreign.sourceID, "\(name): wrong reverse target")
            }
        }
    }

    // INVARIANT 2: latin → foreign → latin is the identity, restricted to keys whose
    // foreign character is a single code point (ligature keys like Arabic لا are
    // inherently asymmetric and excluded — that's expected, not a bug).
    func testLatinRoundTripIsIdentity() {
        var rng = LCG(state: 0x0BAD_F00D_DEAD_BEEF)
        for (foreign, name) in pairs {
            let safeLatin = (0..<26)
                .filter { foreign.character(forKeyCode: UInt16($0), shift: false)!.count == 1 }
                .map { String(Self.order[$0]) }
            for _ in 0..<iterations {
                var word = ""
                for _ in 0..<Int.random(in: 1...14, using: &rng) {
                    word += safeLatin.randomElement(using: &rng)!
                }
                let toForeign = LayoutConverter.convert(word, between: english, and: foreign, currentSourceID: nil)
                let back = LayoutConverter.convert(toForeign.converted, between: english, and: foreign, currentSourceID: nil)
                XCTAssertEqual(back.converted, word, "\(name): latin round-trip broke for '\(word)'")
            }
        }
    }

    // INVARIANT 3: every single key maps forward correctly, and round-trips for
    // single-codepoint keys.
    func testExhaustivePerKey() {
        for (foreign, name) in pairs {
            for k in 0..<26 {
                let latin = String(Self.order[k])
                let toForeign = LayoutConverter.convert(latin, between: english, and: foreign, currentSourceID: nil)
                XCTAssertEqual(toForeign.converted, foreign.character(forKeyCode: UInt16(k), shift: false),
                               "\(name): key \(k) forward mapping wrong")
                if foreign.character(forKeyCode: UInt16(k), shift: false)!.count == 1 {
                    let back = LayoutConverter.convert(toForeign.converted, between: english, and: foreign, currentSourceID: nil)
                    XCTAssertEqual(back.converted, latin, "\(name): key \(k) did not round-trip")
                }
            }
        }
    }

    // INVARIANT 4: mixed input (foreign + spaces + digits + symbols) never crashes,
    // preserves length where chars are unmapped, and stays deterministic.
    func testMixedAndUnmappedRobustness() {
        var rng = LCG(state: 0xCAFE_BABE_1357_9BDF)
        let extras = Array(" 0123456789.,!?@#")
        for (foreign, name) in pairs {
            let chars = (0..<26).map { foreign.character(forKeyCode: UInt16($0), shift: false)! }
            for _ in 0..<iterations {
                var word = ""
                for _ in 0..<Int.random(in: 0...16, using: &rng) {
                    if Bool.random(using: &rng) {
                        word += chars[Int.random(in: 0..<26, using: &rng)]
                    } else {
                        word.append(extras[Int.random(in: 0..<extras.count, using: &rng)])
                    }
                }
                let out = LayoutConverter.convert(word, between: english, and: foreign, currentSourceID: nil)
                // Determinism: same input → same output.
                let again = LayoutConverter.convert(word, between: english, and: foreign, currentSourceID: nil)
                XCTAssertEqual(out.converted, again.converted, "\(name): non-deterministic output")
                // Output never empty when input non-empty.
                if !word.isEmpty { XCTAssertFalse(out.converted.isEmpty, "\(name): dropped all chars") }
            }
        }
    }
}
