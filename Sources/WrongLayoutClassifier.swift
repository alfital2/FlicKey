import Foundation

// Which evidence established the slip; recorded in the diagnostics trail so a
// beta report shows WHY a fix fired (or a false positive believed).
enum SlipSignal: String, Codable, Equatable {
    case misspelled   // misspelled in every working dictionary it could be
    case tell         // structurally impossible form (OrthographyRules)
    case single       // lone letter, judged by its swap alone
}

// A confirmed wrong-layout reading of a word: what it should have been, the
// layout it belongs to (so a multi-layout setup fires toward the layout that
// actually validated, not just "the other one"), and the evidence.
struct WrongLayoutMatch: Equatable {
    let suggestion: String
    let targetSourceID: String?
    let signal: SlipSignal
}

// The classifier's full answer for a completed word. The distinction between
// notSlip and slipWithoutValidSwap exists for diagnostics: "looked intentional"
// and "flagged, but nothing validated the swap" are different field bugs.
enum WrongLayoutVerdict: Equatable {
    case match(WrongLayoutMatch)
    case notSlip                 // looked intentional; leave it alone
    case slipWithoutValidSwap    // near-miss: flagged, but no candidate validated
    case ineligible              // empty, has digits, or no letters
}

// Wrong-layout signal, generalized over the user's enabled layouts. A word
// qualifies as a slip when any of these holds:
//   - it is misspelled in every working dictionary it could have been meant in
//     (the languages of the enabled layouts matching its script), or
//   - it carries a structural tell (OrthographyRules): a character position
//     impossible in its script, or
//   - it is a single letter (spell checkers pass every lone letter, so singles
//     are judged purely by what they swap into).
// It must then swap, on some other enabled layout, into a real word: validated
// by a working dictionary, or by the explicit single-letter table for one-char
// swaps. A dictionary that cannot fail (macOS lists several such languages)
// never validates anything, so a plain typo or an unverifiable guess never
// rewrites the user's text.
struct WrongLayoutClassifier {

    private let spellChecker: SpellChecking

    // Cold-start warm-up: one throwaway query per language forces AppleSpell to
    // load its dictionaries, so the FIRST real word of a session validates
    // correctly instead of missing against a daemon that is still starting.
    func warmDictionaries(for languages: [String]) {
        for language in languages { _ = spellChecker.hasFunctionalDictionary(language) }
    }
    private let candidates: (String) -> [(converted: String, targetSourceID: String?)]
    private let enabledLanguages: () -> [String]

    init(spellChecker: SpellChecking,
         candidates: @escaping (String) -> [(converted: String, targetSourceID: String?)],
         enabledLanguages: @escaping () -> [String] = {
             // ONLY the primary language of each enabled keyboard layout — the
             // narrowest honest signal for "what this user types". NOT the system's
             // preferred-language list: macOS returns its full ~34-language fallback
             // there, and a single lenient member (Spanish/Dutch accept "nv") would
             // make a real slip look intentional and silently stop firing.
             WordScript.primaryLanguages(of: InputSourceCatalog.enabledSources())
         }) {
        self.spellChecker = spellChecker
        self.candidates = candidates
        self.enabledLanguages = enabledLanguages
    }

    func verdict(_ word: String) -> WrongLayoutVerdict {
        guard !word.isEmpty,
              !word.contains(where: { $0.isNumber }),
              word.contains(where: { $0.isLetter })
        else { return .ineligible }

        // Establish the slip evidence in priority order: a lone letter bypasses
        // dictionaries entirely; a structural tell outranks the checker (it holds
        // even when the word collides with a real one); plain misspelling last.
        let signal: SlipSignal
        if word.count == 1 {
            signal = .single
        } else if OrthographyRules.hasWrongLayoutTell(word) {
            signal = .tell
        } else if isMisspelledEverywhere(word) {
            signal = .misspelled
        } else {
            return .notSlip
        }

        for candidate in candidates(word)
        where candidate.converted != word && isRealWord(candidate.converted) {
            return .match(WrongLayoutMatch(suggestion: candidate.converted,
                                           targetSourceID: candidate.targetSourceID,
                                           signal: signal))
        }
        return .slipWithoutValidSwap
    }

    // The other-layout reading of this word, if it is a wrong-layout slip; nil
    // for anything that looks intentional.
    func wrongLayoutMatch(_ word: String) -> WrongLayoutMatch? {
        if case .match(let match) = verdict(word) { return match }
        return nil
    }

    func wrongLayoutSuggestion(_ word: String) -> String? { wrongLayoutMatch(word)?.suggestion }
    func isWrongLayout(_ word: String) -> Bool { wrongLayoutMatch(word) != nil }

    // Misspelled in every working dictionary the word could have been meant in.
    // With no working dictionary for its script, nothing can establish it, so it
    // never counts (only a structural tell can qualify such a word).
    //
    // Informal chat spelling that only drops apostrophes ("hes", "youre", "im") is
    // NOT a slip: the checker flags it, but its correction is the same word with the
    // apostrophe restored, so it reads as intentional English. Applying the same
    // apostrophe-elision tolerance the swap side uses (isApostropheElision) keeps such
    // words from counting as confident wrong-layout matches — they are at most
    // ambiguous. Without this, common contractions that also transliterate to a real
    // target word (e.g. "hes" → Hebrew יקד) become reliable false triggers.
    private func isMisspelledEverywhere(_ word: String) -> Bool {
        let languages = WordScript.spellLanguages(for: word, enabledLanguages: enabledLanguages())
            .filter { spellChecker.hasFunctionalDictionary($0) }
        guard !languages.isEmpty else { return false }
        return languages.allSatisfy {
            spellChecker.isMisspelled(word, language: $0) && !isApostropheElision(word, language: $0)
        }
    }

    // Is the swapped text a real word where it would land? Requires a working
    // dictionary to vouch for it (or the single-letter table for lone letters),
    // and rejects text carrying a structural tell of its own.
    // Whether a converted word is a real word in some enabled-layout language —
    // exposed so the fire path can pick among ambiguous conversion parses (the
    // ArabicPC لا digraph: "bad" beats "ghad") with the same validator that
    // approved the match in the first place.
    func validatesAsRealWord(_ word: String) -> Bool { isRealWord(word) }

    // Apostrophe/geresh forms are the only non-letters that are legitimate INSIDE a word
    // (Hebrew geresh on the w key, informal contractions). Everything else — "/ . \" - [ ] etc.
    private static let inWordPunctuation: Set<Character> = ["'", "\u{05F3}", "\u{2019}"]

    private func isRealWord(_ word: String) -> Bool {
        guard !word.isEmpty, !OrthographyRules.hasWrongLayoutTell(word) else { return false }
        // A dictionary that SPLITS a token on punctuation and validates the fragments (AppleSpell's
        // Hebrew treats "/" — the q key — as a separator) would accept a slash-bearing non-word as
        // "real" (the q→/ false-word class, B26-1). Reject any candidate carrying a non-letter that
        // isn't an in-word apostrophe/geresh, so only genuine words pass.
        guard !word.contains(where: { !$0.isLetter && !Self.inWordPunctuation.contains($0) }) else { return false }
        let languages = WordScript.spellLanguages(for: word, enabledLanguages: enabledLanguages())
        if word.count == 1 {
            let lowered = word.lowercased()
            return languages.contains { WordScript.singleLetterWords(forLanguage: $0).contains(lowered) }
        }
        return languages.contains {
            guard spellChecker.hasFunctionalDictionary($0) else { return false }
            return !spellChecker.isMisspelled(word, language: $0)
                || isApostropheElision(word, language: $0)
        }
    }

    // Informal chat spelling drops apostrophes ("dont", "youre"); dictionaries
    // flag those, but their correction is the same word with the apostrophes
    // restored. Accept exactly that case: correction minus apostrophes equals the
    // word minus apostrophes. Gibberish gets no correction (verified live), and a
    // correction that changes any letter is a different word, so this cannot
    // validate junk.
    private func isApostropheElision(_ word: String, language: String) -> Bool {
        guard let corrected = spellChecker.correction(for: word, language: language) else { return false }
        func stripped(_ s: String) -> String {
            s.lowercased().filter { $0 != "'" && $0 != "\u{2019}" }
        }
        return stripped(corrected) == stripped(word)
    }
}
