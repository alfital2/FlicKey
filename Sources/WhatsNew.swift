import Foundation

// A one-time "what's new" note, introduced per release ONLY when the developer
// chooses to. Shown once per user, never automatically on every version.
//
// The gate is `WhatsNew.current`: set it to a note for a release you want to
// announce, or leave it nil for a silent release. A user sees a given note once;
// bump the note's `version` (any new string) to announce something new later.
struct WhatsNewItem: Equatable {
    let symbol: String   // SF Symbol name shown beside the line
    let text: String
}

struct WhatsNewNote: Equatable {
    let version: String     // identifies this note; a user sees each version once
    let title: String
    let subtitle: String
    let items: [WhatsNewItem]
}

enum WhatsNew {
    // THE DEVELOPER GATE. Non-nil = show this note once to users who have not seen
    // it. nil = no popup this release. Change `version` to announce a new note.
    static let current: WhatsNewNote? = WhatsNewNote(
        version: "0.5.0",
        title: "FlicKey just got better",
        subtitle: "",
        items: [
            WhatsNewItem(symbol: "wand.and.stars",
                text: "Auto-fix: type in the wrong layout and FlicKey corrects it and switches for you, automatically."),
            WhatsNewItem(symbol: "hand.tap.fill",
                text: "Feel it: a gentle haptic tap when the layout switches."),
            WhatsNewItem(symbol: "speaker.wave.2.fill",
                text: "Hear it: a satisfying click, in the sound you pick."),
            WhatsNewItem(symbol: "arrow.uturn.backward",
                text: "Undo an auto-fix: double-tap Option (\u{2325}\u{2325}) right after to revert it and switch the layout back. Do it twice on a word and FlicKey stops auto-fixing it."),
            WhatsNewItem(symbol: "chevron.left.forwardslash.chevron.right",
                text: "The full FlicKey source code is now public on GitHub."),
        ])

    // Pure decision so it is unit-testable: show only when a note exists and its
    // version differs from the last one the user has already seen.
    static func shouldShow(current: WhatsNewNote?, seenVersion: String?) -> Bool {
        guard let current else { return false }
        return current.version != seenVersion
    }
}
