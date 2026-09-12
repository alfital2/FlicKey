import Foundation

// The pure routing decision for an activated app, extracted from AppWatcher so
// it can be unit-tested without NSWorkspace / real apps.
//
// Precedence (covers QA cases B3/B5, C6/C7, D5/D6, J3):
//   1. An explicitly fixed source wins for every app kind.
//   2. Remember mode routes at the app kind's natural scope: app, website, or
//      conversation.
//   3. Undefined/unlisted apps leave the current source untouched.
enum AppRouting {

    enum Decision: Equatable {
        case force(String)     // switch to this input source ID
        case rememberApp
        case conversation      // hand to AppConversationMemory
        case browser           // hand to TabMemory
        case leaveAsIs         // release controllers, don't change layout
    }

    static func decide(rule: InputRule?, kind: AppKind?) -> Decision {
        guard let rule else { return .leaveAsIs }
        if case .source(let id) = rule { return .force(id) }
        guard let kind else { return .leaveAsIs }
        switch (kind, rule) {
        case (.normal, .auto):
            return .rememberApp
        case (.browser, .auto):
            return .browser
        case (.conversation, .auto):
            return .conversation
        case (_, .source), (_, .undefined):
            return .leaveAsIs
        }
    }
}
