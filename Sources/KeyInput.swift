import CoreGraphics
import Foundation

// Low-level synthetic input for the instant "replace what was just typed" path:
// delete N characters, then type a string directly (layout-independent, via
// keyboardSetUnicodeString — the exact glyphs go in regardless of the active
// layout). No clipboard, no pasteboard polling.
//
// Two robustness measures matter for finicky fields (e.g. Spotlight):
//   1. Every event is posted with CLEARED modifier flags, so if the user
//      re-presses Shift mid-burst (rapid repeated double-taps) it can't turn a
//      Backspace into Shift+Delete and skip a deletion.
//   2. The search-field path types `paced` — a few ms between events. Live-search
//      fields (Spotlight, browser toolbars) debounce/reset on each keystroke and
//      drop events under a zero-gap burst, which left a glyph un-converted. Plain
//      text fields don't debounce, so they fire INSTANTLY (no pacing) — keeping
//      the in-place replace snappy, as it was before the search-field fix.
enum KeyInput {
    private static let backspace: CGKeyCode = 51
    private static let stepMicros: useconds_t = 8_000   // gap between paced events

    // Instant burst by default; `paced` inserts a small gap between deletes for
    // live-search fields (Spotlight, browser toolbars), which debounce on each
    // keystroke and drop events under a zero-gap burst.
    static func deleteBackward(_ count: Int, paced: Bool = false) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            postKey(backspace, down: true, source: source)
            postKey(backspace, down: false, source: source)
            if paced { usleep(stepMicros) }
        }
    }

    // `paced`: search fields need a small gap between keystrokes (they drop events
    // under a zero-gap burst). Plain fields pass paced=false for an instant burst.
    static func typeText(_ text: String, paced: Bool = false) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for character in text {
            var units = Array(String(character).utf16)
            postUnicode(&units, down: true, source: source)
            postUnicode(&units, down: false, source: source)
            if paced { usleep(stepMicros) }
        }
    }

    private static func postKey(_ key: CGKeyCode, down: Bool, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        event.flags = []                       // never let a held modifier ride along
        event.post(tap: .cghidEventTap)
    }

    private static func postUnicode(_ units: inout [UniChar], down: Bool, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return }
        event.flags = []
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        event.post(tap: .cghidEventTap)
    }
}
