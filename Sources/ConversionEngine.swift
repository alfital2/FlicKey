import Foundation

enum Language {
    case en
    case he
}

// Character-by-character layout conversion between the US (ABC) and
// Israeli Hebrew-PC keyboard layouts, based on physical key positions.
// Direct port of the Lua ConversionEngine module.
struct ConversionEngine {

    // English → Hebrew (standard Israeli keyboard layout).
    private static let enToHe: [Character: String] = [
        // Top row
        "q": "/", "w": "'", "e": "ק", "r": "ר",
        "t": "א", "y": "ט", "u": "ו", "i": "ן",
        "o": "ם", "p": "פ",
        // Home row
        "a": "ש", "s": "ד", "d": "ג", "f": "כ",
        "g": "ע", "h": "י", "j": "ח", "k": "ל",
        "l": "ך", ";": "ף",
        // Bottom row
        "z": "ז", "x": "ס", "c": "ב", "v": "ה",
        "b": "נ", "n": "מ", "m": "צ",
        // Punctuation / special
        ",": "ת", ".": "ץ", "/": ".",
        "'": ",",
        "`": ";",
    ]

    // Uppercase (shifted) English → Hebrew. Same Hebrew letters as lowercase.
    private static let enToHeShifted: [Character: String] = [
        "Q": "/", "W": "'", "E": "ק", "R": "ר",
        "T": "א", "Y": "ט", "U": "ו", "I": "ן",
        "O": "ם", "P": "פ",
        "A": "ש", "S": "ד", "D": "ג", "F": "כ",
        "G": "ע", "H": "י", "J": "ח", "K": "ל",
        "L": "ך",
        "Z": "ז", "X": "ס", "C": "ב", "V": "ה",
        "B": "נ", "N": "מ", "M": "צ",
    ]

    // Hebrew → English reverse map, built once. First-write-wins: the lowercase
    // map is inserted in full first, so for letters present in both the lowercase
    // mapping takes precedence over the shifted one (matches the Lua build order).
    static let heToEn: [String: Character] = {
        var map: [String: Character] = [:]
        for (en, he) in enToHe {
            // enToHe values are unique, so insertion order within this pass is irrelevant.
            map[he] = en
        }
        for (en, he) in enToHeShifted where map[he] == nil {
            map[he] = en
        }
        return map
    }()

    // Merged EN→HE (lowercase + shifted) used when converting English source text.
    private static let enToHeMerged: [Character: String] = {
        var map = enToHe
        for (k, v) in enToHeShifted {
            map[k] = v
        }
        return map
    }()

    // Detect whether text is predominantly English or Hebrew by counting scalars.
    // Ties go to English (matches Lua: enCount >= heCount).
    static func detectLanguage(_ text: String) -> Language {
        var enCount = 0
        var heCount = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (v >= 0x0041 && v <= 0x005A) || (v >= 0x0061 && v <= 0x007A) {
                enCount += 1
            } else if v >= 0x0590 && v <= 0x05FF {
                heCount += 1
            }
        }
        return enCount >= heCount ? .en : .he
    }

    // Some apps (e.g. WhatsApp) apply macOS "smart quotes", silently turning the
    // straight apostrophe typed via the Hebrew `w` key into a typographic one
    // (’ U+2019). Those variants aren't in the layout map, so the character would
    // pass through unconverted (the "only w breaks" bug). Fold the apostrophe /
    // quote family back to ASCII before mapping. We deliberately touch only
    // non-Hebrew-block characters so language detection is unchanged.
    static func normalizeQuotes(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\u{2018}", "\u{2019}", "\u{201B}", "\u{02BC}", "\u{00B4}", "\u{2032}":
                out.append("'")                      // → U+0027 (the `w` key)
            case "\u{201C}", "\u{201D}", "\u{2033}":
                out.append("\"")                     // → U+0022
            default:
                out.append(ch)
            }
        }
        return out
    }

    // Convert text to the opposite layout. Detects the source language, picks the
    // matching map, replaces mapped characters and passes everything else through.
    // Returns the converted text and the target language.
    static func convert(_ text: String) -> (converted: String, target: Language) {
        let text = normalizeQuotes(text)
        let source = detectLanguage(text)
        var result = ""

        if source == .en {
            for ch in text {
                result += enToHeMerged[ch] ?? String(ch)
            }
            return (result, .he)
        } else {
            for ch in text {
                if let mapped = heToEn[String(ch)] {
                    result.append(mapped)
                } else {
                    result.append(ch)
                }
            }
            return (result, .en)
        }
    }
}
