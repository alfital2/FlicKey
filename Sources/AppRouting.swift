import Foundation

// The pure routing decision for an activated app, extracted from AppWatcher so
// it can be unit-tested without NSWorkspace / real apps.
//
// Precedence (covers QA cases B3/B5, C6/C7, D5/D6, J3):
//   1. An explicitly forced source wins for ANY app — including browsers and
//      conversation apps (force overrides their automatic behavior).
//   2. Otherwise a conversation-provider app (e.g. Teams) → per-conversation.
//   3. Otherwise a browser (rule == .auto) → per-site.
//   4. Otherwise → leave the input source as-is.
enum AppRouting {

    enum Decision: Equatable {
        case force(String)     // switch to this input source ID
        case conversation      // hand to AppConversationMemory
        case browser           // hand to TabMemory
        case leaveAsIs         // release controllers, don't change layout
    }

    static func decide(rule: InputRule?, isConversationApp: Bool) -> Decision {
        if case .source(let id)? = rule { return .force(id) }
        if isConversationApp { return .conversation }
        if case .auto? = rule { return .browser }
        return .leaveAsIs
    }
}
