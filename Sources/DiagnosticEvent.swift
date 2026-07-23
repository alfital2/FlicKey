import Foundation

// The fixed vocabulary of things FlicKey may record when the user opts into
// diagnostics. This is the PRIVACY BOUNDARY: every case carries only categorical
// values — app bundle IDs, input-source IDs, enum tokens, bools, small counts and
// lengths, or a one-way hash. There is deliberately NO free-text field anywhere,
// so a typed character has nowhere it could ever be stored. Privacy by
// construction, not by scrubbing.

enum RoutingKind: String, Codable, Equatable {
    case force, conversation, browser, leaveAsIs
}

enum PanelEventKind: String, Codable, Equatable {
    case shown, dismissed, restored
}

// How a rewrite's result diverged from what FlicKey intended to type.
enum RewriteAnomalyKind: String, Codable, Equatable {
    case orphanFragment   // stale characters survived fused to the replacement
    case tailMutated      // the replacement itself isn't the field's tail
}

// Why the rewrite's delete count fell back to the tracked keystroke length
// instead of the measured on-screen span. On this path a text-service mutation
// is NOT compensated (the pre-span-fix behavior), so a shipping trail must show
// when it was taken — previously this was invisible outside the diag build.
enum SpanFallbackReason: String, Codable, Equatable {
    case axUnreadable     // the focused field's value/caret could not be read
    case spanOutOfRange   // the measured span failed the plausibility cap
}

// Why auto-switch declined a word; the false-negative half of a beta report.
enum AutoSwitchRejectReason: String, Codable, Equatable {
    case learnedException   // the user taught us to leave this word alone
    case noValidSwap        // flagged as a slip, but no layout's reading validated
    case endedStreak        // an intentional word broke an open streak
    case targetDisagreed    // pointed at a different layout than the streak
}

enum DiagnosticEvent: Codable, Equatable {
    case appActivated(bundleID: String)
    case routingDecision(bundleID: String, decision: RoutingKind)
    case layoutSwitch(expected: String?, applied: String)          // input-source IDs
    // keyHash / domainHash are SHORT, SALTED, IRREVERSIBLE tokens (DiagnosticHash)
    // of the conversation name / tab domain: they reveal WHEN the identity changed,
    // never WHAT it is. Logged only on a change, so the trail doesn't repeat.
    case conversationKeyResolved(namespace: String, keyHash: String, hadMemory: Bool)
    case siteResolved(domainHash: String, hadMemory: Bool)
    // The conversation/site memory ACTIONS, tying an identity to a layout: what we
    // applied on entering a remembered chat/site, and what we saved when the user
    // set a layout there. scope is the namespace ("teams"/"slack"/"site"); source
    // is a system input-source ID; keyHash is the salted token (never the name).
    case memoryApplied(scope: String, keyHash: String, source: String)
    case memorySaved(scope: String, keyHash: String, source: String)
    // A conversation app was frontmost but its AX tree couldn't be read (the
    // classic "Teams stopped remembering" cause — the tree isn't built yet).
    case conversationUnreadable(namespace: String)
    case panelEvent(kind: PanelEventKind)
    case autoSwitchStreakOpened(signal: SlipSignal, script: String, wordLength: Int)
    case autoSwitchFired(target: String, signal: SlipSignal)      // input-source ID only
    case autoSwitchUndone(wordsRejected: Int)                     // count, never the words
    case autoSwitchRejected(reason: AutoSwitchRejectReason, script: String, wordLength: Int)
    case autoSwitchRunBroken(by: RegionBreakKind)                 // only while a streak was open
    // After a rewrite, the field's tail didn't match the intended text: a macOS
    // text service (autocorrect/replacement) mutated the buffer around the edit.
    // Categorical only — the mismatching text is never logged.
    case autoSwitchRewriteAnomaly(kind: RewriteAnomalyKind)
    // The rewrite deleted the tracked keystroke count because the on-screen span
    // could not be measured/trusted — the one path where a text-service mutation
    // is not compensated. Categorical only.
    case autoSwitchSpanFallback(reason: SpanFallbackReason)

    // A one-line human rendering, built only from the categorical fields above, so
    // like the schema itself it can never contain typed text.
    var line: String {
        switch self {
        case .appActivated(let b):
            return "app activated: \(b)"
        case .routingDecision(let b, let d):
            return "routing \(b) → \(d.rawValue)"
        case .layoutSwitch(let expected, let applied):
            return "layout switch → \(applied)" + (expected.map { " (expected \($0))" } ?? "")
        case .conversationKeyResolved(let ns, let keyHash, let had):
            return "conversation[\(ns)] → \(keyHash) (memory: \(had ? "yes" : "no"))"
        case .siteResolved(let domainHash, let had):
            return "site → \(domainHash) (memory: \(had ? "yes" : "no"))"
        case .memoryApplied(let scope, let keyHash, let source):
            return "memory applied: \(scope) \(keyHash) → \(source)"
        case .memorySaved(let scope, let keyHash, let source):
            return "memory saved: \(scope) \(keyHash) → \(source)"
        case .conversationUnreadable(let namespace):
            return "conversation[\(namespace)] unreadable (AX not ready)"
        case .panelEvent(let kind):
            return "panel \(kind.rawValue)"
        case .autoSwitchStreakOpened(let signal, let script, let wordLength):
            return "auto-switch streak opened (\(signal.rawValue), \(script), \(wordLength) chars)"
        case .autoSwitchFired(let target, let signal):
            return "auto-switch fired (\(signal.rawValue)) → \(target)"
        case .autoSwitchUndone(let wordsRejected):
            return "auto-switch undone (\(wordsRejected) words rejected)"
        case .autoSwitchRejected(let reason, let script, let wordLength):
            return "auto-switch rejected: \(reason.rawValue) (\(script), \(wordLength) chars)"
        case .autoSwitchRunBroken(let kind):
            return "auto-switch run broken by \(kind.rawValue)"
        case .autoSwitchRewriteAnomaly(let kind):
            return "auto-switch rewrite anomaly: \(kind.rawValue)"
        case .autoSwitchSpanFallback(let reason):
            return "auto-switch span fallback: \(reason.rawValue)"
        }
    }
}

// One recorded event with its timestamp and the app version that produced it.
struct DiagnosticEntry: Codable, Equatable {
    let at: Date
    let event: DiagnosticEvent
    let appVersion: String
}
