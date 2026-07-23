import AppKit
import ApplicationServices

// Per-conversation provider for Slack (com.tinyspeck.slackmacgap — an Electron
// app, so the same Chromium AX-teardown handling in AppConversationMemory /
// ChromiumAX applies unchanged).
//
// Slack, like Teams, puts the open channel/DM in the WINDOW TITLE. Confirmed
// format (captured live):
//
//   "<conversation> (DM) - <Workspace> - Slack"    → direct message
//   "<conversation> - <Workspace> - Slack"         → channel / group
//   "(3) <conversation> - <Workspace> - Slack"     → with unread badge
//   "<Workspace> - Slack"                           → no conversation open
//
// The WORKSPACE is always the last " - " segment before "Slack"; the conversation
// is everything before it. We keep any "(DM)"/type suffix (it's constant, and it
// disambiguates a DM from a channel of the same name) and strip unread badges so
// the key doesn't fragment as counts change.
struct SlackConversationProvider: ConversationProvider {

    let namespace = "slack"
    let displayName = "Slack"
    let bundleIDs = ["com.tinyspeck.slackmacgap"]

    func context(pid: pid_t) -> ConversationContext {
        guard let title = focusedWindowTitle(pid: pid) else { return .unreadable }
        if let key = Self.conversationKey(fromWindowTitle: title) { return .conversation(key) }
        return .notAConversation
    }

    // MARK: - Pure parser (refine from captured titles)

    static func conversationKey(fromWindowTitle rawTitle: String) -> String? {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only key Slack windows.
        for suffix in [" - Slack", " | Slack"] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !title.isEmpty, title != "Slack" else { return nil }

        // Strip a leading unread badge "(12) " or a trailing "(12 new items)".
        title = title.replacingOccurrences(of: #"^\(\d+\)\s+"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s*\(\d+ new items?\)"#, with: "", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespaces)

        // Drop the trailing workspace segment; the conversation is everything
        // before it. A single segment (no workspace) is the workspace home / no
        // open conversation → not a conversation.
        let parts = title.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        let key = parts.dropLast().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }
}
