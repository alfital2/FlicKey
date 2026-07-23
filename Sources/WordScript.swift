import Foundation

// Script and language knowledge for wrong-layout detection: which script a word
// is written in, which spellcheck languages could judge it on this user's
// machine, and the few words a bare single letter can legitimately be.
enum WordScript {

    enum Script: String { case latin, hebrew, arabic, cyrillic, greek }

    // The script of a word, decided by its first non-Latin scalar. A single
    // foreign scalar decides, so a mixed word (a slip mid-passage) is judged by
    // the script the user was actually producing.
    static func script(for word: String) -> Script {
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x05FF: return .hebrew
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF: return .arabic
            case 0x0400...0x04FF, 0x0500...0x052F: return .cyrillic
            case 0x0370...0x03FF, 0x1F00...0x1FFF: return .greek
            default: continue
            }
        }
        return .latin
    }

    // The script a spellcheck language code writes in ("ru" → cyrillic). Region
    // tags are stripped in both spellings ("pt_BR" and "pt-BR" → "pt"). Unknown
    // codes default to latin, the script of every layout FlicKey can't place.
    static func script(forLanguage code: String) -> Script {
        let base = code.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? code
        switch base {
        case "he", "yi": return .hebrew
        case "ar", "ars", "fa", "ur": return .arabic
        case "ru", "uk", "bg", "be", "sr", "mk", "kk": return .cyrillic
        case "el": return .greek
        default: return .latin
        }
    }

    // Candidate spellcheck languages for a word: the languages of the user's
    // enabled layouts whose script matches the word's, deduplicated in order.
    // Empty when no enabled layout covers the word's script — FlicKey only judges
    // words in scripts the user actually types, so pasted or stray text in an
    // unsupported script is simply ignored rather than checked against a bundled
    // dictionary the user never chose.
    static func spellLanguages(for word: String, enabledLanguages: [String]) -> [String] {
        let target = script(for: word)
        var seen = Set<String>()
        return enabledLanguages.filter {
            script(forLanguage: $0) == target && seen.insert($0).inserted
        }
    }

    // The only words a bare single letter can be in each language. Spell checkers
    // pass every lone letter unflagged (verified live), so single-character swaps
    // are validated against this explicit list instead. Hebrew and Arabic single
    // letters are prefixes that attach to the next word, never standalone words.
    static func singleLetterWords(forLanguage code: String) -> Set<String> {
        let base = code.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? code
        switch base {
        case "en": return ["i", "a"]
        case "ru": return ["и", "а", "в", "к", "с", "о", "у", "я"]
        case "uk": return ["і", "й", "у", "в", "з", "а", "о", "є", "я"]
        case "el": return ["ο", "η"]
        case "es": return ["y", "a", "o", "e"]
        case "fr": return ["a", "à", "y"]
        default: return []
        }
    }

    // The languages the user actively types: each enabled layout's PRIMARY code,
    // deduplicated in order. Never the full advertised list — Apple's ABC layout
    // claims ~97 Latin languages, and feeding them all into detection lets any
    // lenient dictionary (Dutch accepts "nv") veto a real slip.
    static func primaryLanguages(of sources: [InputSourceInfo]) -> [String] {
        var seen = Set<String>()
        return sources.compactMap { $0.languageCodes.first }.filter { seen.insert($0).inserted }
    }

}
