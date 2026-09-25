import Foundation

// Recent input-source switches FlicKey made on its own (a forced app, a
// remembered app/site/conversation), so every memory can tell the system's
// echo of those switches from a user's own layout change.
//
// The input-source notification is system-wide and carries no cause. After a
// switch the OS delivers a prompt echo plus delayed "settling" duplicates
// (~330ms, see ConversationMemoryCore), and TISSelectInputSource is async, so a
// notification in flight can still report the pre-switch source. Under rapid
// app switching those echoes land after ANOTHER app became frontmost: Terminal's
// forced English echoed while WhatsApp was active and was learned as WhatsApp's
// "last used" layout. A one-shot, per-owner ignore token cannot cover that, so
// all owners record here and all learners consult the same window.
//
// Trade-off: a genuine user change to a source involved in a switch less than
// `window` ago is treated as an echo. That only affects a change made within a
// fraction of a second of arriving, and the next change is learned normally.
struct ProgrammaticSwitchLedger {

    private struct Entry {
        let target: String
        let before: String?
        let at: TimeInterval
        // Once the target has been reported, a later report of the pre-switch
        // source is a real change, not an in-flight notification.
        var targetObserved: Bool
    }

    let window: TimeInterval
    private var entries: [Entry] = []

    init(window: TimeInterval = 0.8) {
        self.window = window
    }

    mutating func record(target: String, before: String?, at now: TimeInterval) {
        prune(now)
        entries.append(Entry(target: target, before: before, at: now,
                             targetObserved: before == target))
    }

    // The newest switch still settling, if any. A request can be in flight
    // while the current source still reads as the requested one, so callers
    // must re-issue their own switch when this differs from what they want.
    func pendingTarget(at now: TimeInterval) -> String? {
        entries.last(where: { now - $0.at < window })?.target
    }

    mutating func isEcho(_ source: String, at now: TimeInterval) -> Bool {
        prune(now)
        var echo = false
        for i in entries.indices {
            if entries[i].target == source {
                entries[i].targetObserved = true
                echo = true
            } else if !entries[i].targetObserved, entries[i].before == source {
                echo = true
            }
        }
        return echo
    }

    private mutating func prune(_ now: TimeInterval) {
        entries.removeAll { now - $0.at >= window }
    }
}

// The app-wide ledger. Main-thread only, like every caller.
enum ProgrammaticSwitches {
    private static var ledger = ProgrammaticSwitchLedger()
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // Switches to a remembered/forced source and records it as FlicKey's own.
    static func apply(_ sourceID: String) {
        let current = InputSourceManager.currentSourceID()
        let pending = ledger.pendingTarget(at: now)
        guard current != sourceID || (pending != nil && pending != sourceID) else { return }
        ledger.record(target: sourceID, before: current, at: now)
        InputSourceManager.switchTo(sourceID: sourceID, force: true)
    }

    static func isEcho(_ sourceID: String) -> Bool {
        ledger.isEcho(sourceID, at: now)
    }

    #if DEBUG
    static func resetForTesting() { ledger = ProgrammaticSwitchLedger() }
    #endif
}
