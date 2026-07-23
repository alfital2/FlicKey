import Foundation

// Pure decision + email text for the opt-in beta that shares "words that should
// not have been auto-fixed" (the learned blocklist) so auto-switch can improve.
//
// This is the one place FlicKey would send words the user actually typed, so it
// is gated entirely on DiagnosticConsent.shareBlockedWordsEnabled (off by
// default), never sends without the user seeing the exact words and pressing Send,
// and prompts at most once per interval and only when there is something new.
//
// No Keychain, no UI, so the decision is deterministically unit-testable.
enum BlockedWordsSharing {
    // At most one prompt per this window, so an opted-in user is never nagged.
    static let interval: TimeInterval = 7 * 24 * 60 * 60   // 7 days

    struct Decision: Equatable {
        var shouldPrompt: Bool
        var newWords: [String]   // blocked words not offered in a previous prompt
    }

    // `blocked` = words currently past the block threshold; `alreadyOffered` =
    // words offered in a prior prompt. Prompt only when the interval has elapsed
    // AND there is at least one word we have not offered before.
    static func decide(now: TimeInterval, lastPromptAt: TimeInterval,
                       blocked: [String], alreadyOffered: Set<String>) -> Decision {
        let newWords = blocked.filter { !alreadyOffered.contains($0) }.sorted()
        let due = now - lastPromptAt >= interval
        return Decision(shouldPrompt: due && !newWords.isEmpty, newWords: newWords)
    }

    // The email body a user sends us. It shows exactly the words (full
    // transparency) plus the random install ID so they can later request deletion.
    // No em dashes.
    static func report(words: [String], installID: String, appVersion: String)
        -> (subject: String, body: String) {
        let subject = "FlicKey auto-switch feedback [\(appVersion)]"
        var b = ""
        b += "These words should not have been auto-fixed (learned from my use):\n\n"
        for w in words.sorted() { b += "  \(w)\n" }
        b += "\n"
        b += "Words: \(words.count)\n"
        b += "App: \(appVersion)\n"
        b += "Install ID: \(installID)\n\n"
        b += "Shared because I opted in to help improve FlicKey auto-switch. These "
        b += "are single words FlicKey wrongly converted, so it can learn to leave "
        b += "them alone.\n"
        return (subject, b)
    }
}
