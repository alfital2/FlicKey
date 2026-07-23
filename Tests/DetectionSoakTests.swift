import XCTest

// Seeded soaks of the detection decision layer. Each drives a real component with
// a random event stream and checks invariants after every step.
final class DetectionSoakTests: XCTestCase {

    // MARK: - WordAccumulator: run / current can never desync (the exact class of
    // the "backspace across a word boundary" bug).

    func testAccumulatorConsistencySoak() {
        let letters = Array("abcio ,.;'".map { $0 })   // real letters + layout punctuation
        Soak.run("accumulator") { rng, _ in
            var acc = WordAccumulator()
            var log: [String] = []
            let ops = rng.int(150..<600)
            for _ in 0..<ops {
                let roll = rng.int(0..<100)
                let stroke: KeyStroke
                switch roll {
                case 0..<60:  stroke = .letter(rng.pick(letters))
                case 60..<78: stroke = .space
                case 78..<93: stroke = .backspace
                default:      stroke = .hardBreak
                }
                log.append("\(stroke)")
                let wasLetter: Bool = { if case .letter = stroke { return true }; return false }()
                _ = acc.feed(stroke)

                if rng.chance(40) {
                    let keep = String((0..<rng.int(0..<4)).map { _ in rng.pick(letters) })
                    acc.resetRun(keeping: keep)
                    log.append("resetRun('\(keep)')")
                }

                // INVARIANT 1: current is always exactly the run's tail after the
                // last space — the property whose violation was the desync bug.
                let expectedCurrent: String = {
                    if let idx = acc.run.lastIndex(of: " ") {
                        return String(acc.run[acc.run.index(after: idx)...])
                    }
                    return acc.run
                }()
                if acc.current != expectedCurrent {
                    return "current='\(acc.current)' but run tail='\(expectedCurrent)' (run='\(acc.run)')\nlast ops: \(log.suffix(15))"
                }
                // INVARIANT 2: the run is bounded right after a letter (the cap).
                if wasLetter && acc.run.count > 120 {
                    return "run exceeded cap after a letter: \(acc.run.count)\nlast ops: \(log.suffix(15))"
                }
            }
            return nil
        }
    }

    // MARK: - AutoSwitchStreak: differential against an independent model.

    func testStreakDifferentialSoak() {
        let targets = ["HE", "RU", nil as String?]
        Soak.run("streak") { rng, _ in
            var streak = AutoSwitchStreak(threshold: 2)
            var refCount = 0, refHasMulti = false
            var refTarget: String? = nil
            var log: [String] = []
            let ops = rng.int(100..<400)
            for _ in 0..<ops {
                if rng.chance(25) {
                    streak.breakRun()
                    refCount = 0; refHasMulti = false
                    log.append("breakRun")
                    if streak.count != 0 { return "count != 0 after breakRun (\(streak.count))" }
                    continue
                }
                let ordinary = rng.chance(3)
                let single = rng.chance(3)
                let target = rng.pick(targets)
                let word: AutoSwitchStreak.Word = ordinary
                    ? .ordinary
                    : .wrongLayout(targetSourceID: target, isSingleLetter: single)
                log.append("\(word)")

                // Independent reference model of the arming rule.
                let expectedArmed: Bool
                if ordinary {
                    refCount = 0; refHasMulti = false; refTarget = nil
                    expectedArmed = false
                } else {
                    if refCount > 0 && target != refTarget { refCount = 0; refHasMulti = false }
                    if refCount == 0 { refTarget = target }
                    refCount += 1
                    if !single { refHasMulti = true }
                    expectedArmed = refCount >= 2 && refHasMulti
                }

                let actual = streak.word(word)
                if actual != expectedArmed {
                    return "armed=\(actual) expected=\(expectedArmed) (refCount=\(refCount), hasMulti=\(refHasMulti))\nlast ops: \(log.suffix(15))"
                }
                if streak.count != refCount {
                    return "count=\(streak.count) expected=\(refCount)\nlast ops: \(log.suffix(15))"
                }
                // INVARIANT: arming ALWAYS requires ≥2 words and a multi-letter one.
                if actual && !(refCount >= 2 && refHasMulti) {
                    return "armed without meeting the precondition\nlast ops: \(log.suffix(15))"
                }
            }
            return nil
        }
    }

    // MARK: - WrongLayoutClassifier: robustness + determinism + contract under fuzz.

    func testClassifierRobustnessSoak() {
        let classifier = WrongLayoutClassifier(
            spellChecker: SoakSpell(),
            candidates: { SoakLayouts.candidates($0) },
            enabledLanguages: { ["en", "he"] })

        // A wide, weird character pool: real scripts, punctuation, digits, spaces,
        // and awkward unicode — the classifier must never crash or be inconsistent.
        let pool = Array("abcio ,.;'שלוםабвγ12!\u{05F3}\u{2019}\u{0000}\u{200B}😀".map { $0 })

        Soak.run("classifier") { rng, _ in
            let len = rng.int(0..<14)
            let word = String((0..<len).map { _ in rng.pick(pool) })

            // Determinism: identical input ⇒ identical verdict, every time.
            let a = classifier.verdict(word)
            let b = classifier.verdict(word)
            if a != b { return "non-deterministic verdict for '\(word)': \(a) vs \(b)" }

            // Contract: a match's suggestion is a real candidate, non-empty, != input.
            if case .match(let m) = a {
                let candidateStrings = SoakLayouts.candidates(word).map { $0.converted }
                if m.suggestion.isEmpty { return "empty suggestion for '\(word)'" }
                if m.suggestion == word { return "suggestion equals input for '\(word)'" }
                if !candidateStrings.contains(m.suggestion) {
                    return "suggestion '\(m.suggestion)' not among candidates \(candidateStrings) for '\(word)'"
                }
            }
            // wrongLayoutMatch must agree with verdict.
            let matched = classifier.wrongLayoutMatch(word) != nil
            let isMatchVerdict: Bool = { if case .match = a { return true }; return false }()
            if matched != isMatchVerdict {
                return "wrongLayoutMatch(\(matched)) disagrees with verdict(\(a)) for '\(word)'"
            }
            return nil
        }
    }
}

// MARK: - Fixtures (deterministic, machine-independent)

// A spell checker over tiny fixed dictionaries; en and he are "functional".
private struct SoakSpell: SpellChecking {
    let en: Set<String> = ["hi", "so", "cab", "ace", "ice", "i", "a"]
    let he: Set<String> = ["של", "שלום", "בי", "מה"]
    func hasFunctionalDictionary(_ language: String) -> Bool { language == "en" || language == "he" }
    func isMisspelled(_ word: String, language: String) -> Bool {
        guard hasFunctionalDictionary(language) else { return false }
        return !(language == "en" ? en : he).contains(word.lowercased())
    }
    func correction(for word: String, language: String) -> String? { nil }
}

// A fixed en↔he bijection so candidates() is deterministic on every machine.
private enum SoakLayouts {
    static let enChars = Array("abcdefghijklmnopqrstuvwxyz")
    static let heChars = Array("אבגדהוזחטיכלמנסעפצקרשתךםןף")   // 26 distinct

    static func swap(_ word: String, from: [Character], to: [Character]) -> String? {
        var out = ""
        for ch in word {
            guard let i = from.firstIndex(of: Character(ch.lowercased())) else { return nil }
            out.append(to[i])
        }
        return out
    }
    static func candidates(_ word: String) -> [(converted: String, targetSourceID: String?)] {
        var result: [(String, String?)] = []
        if let he = swap(word, from: enChars, to: heChars), he != word { result.append((he, "he")) }
        if let en = swap(word, from: heChars, to: enChars), en != word { result.append((en, "en")) }
        return result
    }
}
