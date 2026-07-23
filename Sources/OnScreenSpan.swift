import Foundation

// Pure helper for the synthetic rewrite. Auto-switch tracks the KEYSTROKES the
// user made and deletes that many characters before retyping the conversion. But
// macOS text services (autocorrect, text replacement, inline autocomplete) can
// EXPAND those keystrokes on screen — "בשמ" becomes "בשמאל" — so a keystroke-count
// delete removes too few characters and orphans a stale prefix next to the
// replacement ("בשcan i "). The correct delete count is the ACTUAL on-screen
// length of the run's words, measured from the field content.
//
// The tracked run is `w1 w2 … wN ` (each word followed by a soft space; the fire
// triggers on that final space). On screen the span to delete is exactly the last
// N words plus their trailing/interleaving spaces — however long autocorrect made
// each word. This walks back from the caret over N (spaces, word) groups.
enum OnScreenSpan {
    static func length(beforeCaret chars: [Character], words: Int) -> Int {
        guard words > 0 else { return 0 }
        var i = chars.count
        // Any whitespace separates words — a text service can substitute a
        // non-breaking space (U+00A0) for a typed space, and treating it as a word
        // character would walk past the run into the user's prior text.
        for _ in 0..<words {
            while i > 0 && chars[i - 1].isWhitespace { i -= 1 }   // trailing / separating spaces
            while i > 0 && !chars[i - 1].isWhitespace { i -= 1 }  // one word
        }
        return chars.count - i
    }
}

// Post-rewrite self-check: after a synthetic delete+retype, the field's tail
// should be exactly the text FlicKey typed, preceded by a word boundary. A macOS
// text service can break that two ways — leave a stale fragment fused before the
// replacement (orphanFragment), or mutate the replacement itself so it isn't the
// tail at all (tailMutated). Pure so it is unit-tested; used only for a
// diagnostic log line, never to drive an edit.
enum RewriteCheck {
    static func anomaly(beforeCaret before: [Character], expected: [Character]) -> RewriteAnomalyKind? {
        guard !expected.isEmpty else { return nil }
        guard before.count >= expected.count,
              Array(before.suffix(expected.count)) == expected else { return .tailMutated }
        let boundary = before.count - expected.count
        if boundary == 0 { return nil }                 // the replacement is the whole content
        return before[boundary - 1] == " " ? nil : .orphanFragment
    }

    // Stronger check, used when the pre-rewrite field state was readable: the
    // field after the rewrite must be exactly (pre-rewrite content minus the
    // deleted span) plus the typed text. Unlike the suffix heuristic above, this
    // also catches a SPACE-SEPARATED orphan (a multi-word expansion's leftover,
    // e.g. "On my " surviving before the replacement) and any over-delete into
    // the user's prior text — the whole model-vs-screen class.
    static func residueAnomaly(actual: [Character], expected: [Character],
                               typed: [Character]) -> RewriteAnomalyKind? {
        guard !typed.isEmpty, actual != expected else { return nil }
        // The typed text survived as the tail → the damage is around it (stale
        // fragment left, or prior text eaten). Otherwise the replacement itself
        // was mutated by a text service.
        let typedIntact = actual.count >= typed.count && Array(actual.suffix(typed.count)) == typed
        return typedIntact ? .orphanFragment : .tailMutated
    }
}
