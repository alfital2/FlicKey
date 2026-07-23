import AppKit

// Seam over the system spell checker so detection logic is unit-testable
// (NSSpellChecker is environment-dependent and unreliable headless/CI).
protocol SpellChecking {
    func isMisspelled(_ word: String, language: String) -> Bool
    // Whether the language has a WORKING dictionary on this machine.
    // availableLanguages alone lies: on a stock machine el/ar/uk are listed yet
    // their checkers flag nothing (verified live), so trusting the list would
    // validate garbage as "a real word". Detection must never fire through a
    // dictionary that cannot fail.
    func hasFunctionalDictionary(_ language: String) -> Bool
    // The checker's best correction for a misspelled word, or nil. Used to accept
    // informal apostrophe elision ("dont" corrects to "don't"); gibberish gets no
    // correction (verified live), so this can't validate junk.
    func correction(for word: String, language: String) -> String?
}

final class SystemSpellChecker: SpellChecking {

    private var functionalCache: [String: Bool] = [:]

    func isMisspelled(_ word: String, language: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: language,
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location != NSNotFound
    }

    func correction(for word: String, language: String) -> String? {
        NSSpellChecker.shared.correction(
            forWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word, language: language, inSpellDocumentWithTag: 0)
    }

    // A dictionary counts as functional only if it actually flags script-
    // appropriate gibberish. Cached per language; main-thread only, like every
    // NSSpellChecker call in the app.
    func hasFunctionalDictionary(_ language: String) -> Bool {
        if let cached = functionalCache[language] { return cached }
        let works = NSSpellChecker.shared.availableLanguages.contains(language)
            && isMisspelled(Self.gibberish(for: language), language: language)
        functionalCache[language] = works
        return works
    }

    // Junk no working dictionary should accept, in the language's own script.
    private static func gibberish(for language: String) -> String {
        switch WordScript.script(forLanguage: language) {
        case .latin: return "qzkxvjw"
        case .hebrew: return "קץךגחט"
        case .arabic: return "ضصثقفغ"
        case .cyrillic: return "гшдуюеч"
        case .greek: return "ςθιψκζ"
        }
    }
}
