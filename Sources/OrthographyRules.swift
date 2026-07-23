import Foundation

// Structural spelling rules that expose a wrong-layout slip even when the word
// happens to spell something a dictionary would accept, or when no working
// dictionary exists for the language (common: macOS lists languages whose
// checker flags nothing). Each rule marks a character position that is
// impossible in text genuinely written in that script, because the offending
// character sits on a key the user hits when typing another language on this
// layout.
//
// The shared principle: a final-only letter form, or an end-of-sentence
// punctuation mark, is a tell only when a LETTER follows it — mid-word is
// impossible, but at the word's effective end it is ordinary writing. (The
// tracker glues layout-punctuation into words, so "שלום." or "κάνεις;" arrive
// with their trailing mark attached; those must not be flagged.)
enum OrthographyRules {

    static func hasWrongLayoutTell(_ word: String) -> Bool {
        switch WordScript.script(for: word) {
        case .hebrew: return hebrewTell(word)
        case .greek: return greekTell(word)
        case .arabic: return arabicTell(word)
        case .cyrillic, .latin: return false
        }
    }

    // True when a letter appears anywhere after position i.
    private static func letterFollows(_ chars: [Character], _ i: Int) -> Bool {
        chars[(i + 1)...].contains { $0.isLetter }
    }

    // MARK: - Hebrew

    // The geresh forms the layouts produce: ' (Hebrew-PC), ׳ (Hebrew), ’ (Hebrew-QWERTY).
    private static let gereshChars: Set<Character> = ["'", "\u{05F3}", "\u{2019}"]
    // A geresh is only written after these letters — loan sounds (ג'=j, ז'=zh,
    // צ'=ch, ח'=kh) and abbreviations like ה'. Anywhere else it is the w key on
    // the Hebrew layout. (An abbreviation geresh can follow ANY letter — מס',
    // עמ' — but so does English ending in w typed on Hebrew, e.g. how → ים';
    // the dictionary side of the two-sided test is what separates those, so an
    // unlisted preceder stays a tell.)
    private static let gereshPreceders: Set<Character> = ["ג", "ז", "ח", "צ", "ץ", "ה"]
    // Final letter forms; they never appear before another letter.
    private static let hebrewFinalForms: Set<Character> = ["ך", "ם", "ן", "ף", "ץ"]

    private static func hebrewTell(_ word: String) -> Bool {
        let chars = Array(word)
        for (i, ch) in chars.enumerated() {
            if gereshChars.contains(ch) {
                let preceder: Character? = i > 0 ? chars[i - 1] : nil
                if preceder == nil || !gereshPreceders.contains(preceder!) { return true }
            }
            if hebrewFinalForms.contains(ch) && letterFollows(chars, i) { return true }
        }
        return false
    }

    // MARK: - Greek

    private static func greekTell(_ word: String) -> Bool {
        let chars = Array(word)
        for (i, ch) in chars.enumerated() {
            // Final sigma before another letter is the w key; κάνεις; stays legit.
            if ch == "ς" && letterFollows(chars, i) { return true }
            // The q key produces the erotimatiko; inside a word it is a slip, at
            // the end it is an ordinary Greek question mark.
            if (ch == ";" || ch == "\u{037E}") && letterFollows(chars, i) { return true }
        }
        return false
    }

    // MARK: - Arabic

    // Taa marbuta and alef maqsura are strictly word-final. (Persian's ی is a
    // different codepoint, so Persian text never trips this.)
    private static let arabicFinalOnly: Set<Character> = ["ة", "ى"]
    // Arabic comma and semicolon; produced by letter-adjacent keys, ordinary at a
    // word's end but impossible before more letters.
    private static let arabicPunctuation: Set<Character> = ["\u{060C}", "\u{061B}"]

    private static func arabicTell(_ word: String) -> Bool {
        let chars = Array(word)
        for (i, ch) in chars.enumerated() {
            if arabicFinalOnly.contains(ch) && letterFollows(chars, i) { return true }
            if arabicPunctuation.contains(ch) && letterFollows(chars, i) { return true }
        }
        return false
    }
}
