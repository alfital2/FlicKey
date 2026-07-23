import AppKit
import ApplicationServices

// Per-conversation provider for Microsoft Teams (the WebView2 "new Teams").
//
// Teams does not expose its compose box or a conversation heading to the
// Accessibility API, but it DOES put the open conversation's name in the
// window title, which changes every time you switch chats. AppConversationMemory
// POLLS this title (Teams tears its AX tree down when backgrounded, so title-
// change events can't be relied on). Observed formats (English UI):
//
//   "Chat | <name> (External) | Microsoft Teams"     → 1:1 / group chat
//   "Chat | <a> and <b> (External) | Microsoft Teams" → unnamed chat
//   "Chat | <you> (You) | Microsoft Teams"            → self-chat
//   "Teams and Channels | (External) | Microsoft Teams" → channel LIST (no convo)
//   "Assignments | (External) | Microsoft Teams"      → app tab (no convo)
//   "Chat | Microsoft Teams"                          → chat list (no convo)
//
// We do NOT trust the leading MODULE label ("Chat"/"Calendar"/…): Teams flaps it
// between "Chat" and "Calendar" for the SAME open chat, so gating on it made
// detection intermittent. We drop that first segment and key on the conversation
// NAME that follows (with the constant trailing org/email, in enterprise builds,
// kept — they don't change, so the key stays stable). Ignoring the module also
// means the feature works regardless of the Teams UI language.
struct TeamsConversationProvider: ConversationProvider {

    let namespace = "teams"
    let displayName = "Microsoft Teams"

    // "new Teams" is com.microsoft.teams2; the classic Electron client used
    // com.microsoft.teams. Handle both (teams2 first — it's the installed one).
    let bundleIDs = ["com.microsoft.teams2", "com.microsoft.teams"]

    func context(pid: pid_t) -> ConversationContext {
        guard let title = focusedWindowTitle(pid: pid) else { return .unreadable }
        if let key = Self.conversationKey(fromWindowTitle: title) { return .conversation(key) }
        return .notAConversation
    }

    // MARK: - Pure parser (unit-tested)

    private static let teamsSuffix = " | Microsoft Teams"

    // Returns a stable per-conversation key, or nil if the title does not
    // represent an open chat conversation.
    static func conversationKey(fromWindowTitle rawTitle: String) -> String? {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Teams may prefix an unread-count badge, e.g. "(3) Chat | … ". Strip it
        // so the key doesn't fragment as the count changes.
        title = stripLeadingUnreadBadge(title)

        // Must be a Teams window.
        guard title.hasSuffix(teamsSuffix) else { return nil }
        let body = String(title.dropLast(teamsSuffix.count))
            .trimmingCharacters(in: .whitespaces)

        // Drop the leading MODULE segment ("Chat" / "Calendar" / …) — an
        // untrusted, flapping label — and key on everything after it. A title
        // with no module→name separator (a bare list view) has no name.
        guard let sep = body.range(of: " | ") else { return nil }
        // Greedy: everything after the first separator, so a conversation name
        // (and the trailing org/email) that itself contains " | " survives whole.
        let middle = String(body[sep.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Strip the trailing tenant tag ("(External)"/"(You)"/…). Live testing
        // showed Teams retitles in two stages — the tag flaps on/off for the
        // SAME conversation (e.g. "Alex (External)" then "Alex"), which would
        // split a conversation's memory across two keys.
        let key = stripTrailingTenantTag(middle)

        // Must be an actual name, not just a bare tag (non-conversation contexts
        // like the channel list show "(External)" with no name).
        guard !key.isEmpty else { return nil }
        return key
    }

    // MARK: - Pure parser helpers

    // Remove a leading unread badge "(<digits>) ".
    private static func stripLeadingUnreadBadge(_ s: String) -> String {
        guard let r = s.range(of: #"^\(\d+\)\s+"#, options: .regularExpression) else { return s }
        return String(s[r.upperBound...])
    }

    // Remove a single trailing Teams relationship tag. The tag BEGINS with a
    // known keyword (External/Internal/Guest/You) but may carry extra words —
    // live capture showed "(External unfamiliar)", not just "(External)", and
    // the qualifier can change for the same conversation. So match the keyword
    // plus any trailing words, while leaving unrelated parentheticals (e.g.
    // "Budget (Q3)") intact so distinct chats don't collide.
    private static func stripTrailingTenantTag(_ s: String) -> String {
        guard let r = s.range(of: #"\s*\((?:External|Internal|Guest|You)\b[^()]*\)\s*$"#,
                              options: .regularExpression) else { return s }
        return String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

}
