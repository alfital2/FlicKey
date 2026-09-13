import Foundation

// The pure decision core of per-conversation input memory, separated from the
// Accessibility/observer wiring (AppConversationMemory) so the state machine
// can be unit-tested deterministically — no AX, no system input sources.
//
//   enter(key:)    — the open conversation changed; apply its remembered input
//                    source if we have one (unknown or nil → do nothing).
//   inputChanged() — the user changed layout; remember it for the current
//                    conversation (no current conversation → don't save).
//   reset()        — left the app; forget the active conversation so a later
//                    input change is never written under a stale key. This is
//                    the invariant that makes the controllers mutually safe.
//
// Applying a remembered source fires the OS input-source-change notification we
// must not re-save. Measured behavior (scripts/tis-notify-probe.swift): the
// confirming notification lands ~5–15ms after our switch, BUT under rapid
// switching the OS also emits EXTRA delayed "settling" notifications ~330ms
// later — several of them — all reporting the final applied source. A one-shot
// guard consumed only the first; the delayed duplicates then got saved under
// whatever key the user had since switched to, corrupting per-site memory (the
// Safari tab flip-flop).
//
// So we remember the LAST source we auto-applied and when, and ignore any
// input-change that reports that same source within `echoWindow` of the apply —
// covering the prompt echo and all the delayed settling duplicates. A change to
// a DIFFERENT source is a genuine user choice and is saved at once (so "switch
// chat → set language" is unaffected), and it supersedes the pending echo.
// Tracking only the LAST applied source (not a set) means a genuine change to a
// layout we applied for a PREVIOUS key is still saved.
//
// All side-effecting dependencies are injected, defaulting to the real
// implementations, so tests substitute spies and control the clock.
final class ConversationMemoryCore {

    let namespace: String
    private(set) var currentKey: String?

    // The source we most recently auto-applied, and when. nil = no pending echo.
    private var lastAppliedSource: String?
    private var lastAppliedAt: TimeInterval = 0
    // TISSelectInputSource is asynchronous. A notification already in flight can
    // arrive after enter() but before the requested source becomes current. In
    // that short transition it still reports the pre-apply source and must not
    // be learned over the destination key.
    private var sourceBeforeApply: String?
    private var hasObservedAppliedSource = false

    private let lookup: (String, String) -> String?
    private let store: (String, String, String) -> Void
    private let applySource: (String) -> Void
    private let currentSource: () -> String?
    private let now: () -> TimeInterval
    // Must comfortably exceed the OS's worst-case apply→notification lag,
    // including the delayed settling burst (~330ms measured), so none of those
    // echoes is mistaken for a user change.
    private let echoWindow: TimeInterval
    // Optional diagnostics hooks (default no-ops). onApplied fires when a
    // remembered source is applied on entering a conversation; onSaved when the
    // user's layout choice is stored for the current conversation. Each receives
    // the source AND the key it was for, so the trail can tie the layout to the
    // identity. Pure-core tests leave them nil, so behavior is unchanged.
    private let onApplied: (_ source: String, _ key: String) -> Void
    private let onSaved: (_ source: String, _ key: String) -> Void

    init(namespace: String,
         lookup: @escaping (String, String) -> String? = ContextMemoryStore.sourceID,
         store: @escaping (String, String, String) -> Void = ContextMemoryStore.set,
         applySource: @escaping (String) -> Void = { InputSourceManager.switchTo(sourceID: $0) },
         currentSource: @escaping () -> String? = { InputSourceManager.currentSourceID() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         echoWindow: TimeInterval = 0.8,
         onApplied: @escaping (_ source: String, _ key: String) -> Void = { _, _ in },
         onSaved: @escaping (_ source: String, _ key: String) -> Void = { _, _ in }) {
        self.namespace = namespace
        self.lookup = lookup
        self.store = store
        self.applySource = applySource
        self.currentSource = currentSource
        self.now = now
        self.echoWindow = echoWindow
        self.onApplied = onApplied
        self.onSaved = onSaved
    }

    func enter(key: String?) {
        guard key != currentKey else { return }   // debounce identical retitles
        currentKey = key
        guard let key, let source = lookup(namespace, key) else { return }
        sourceBeforeApply = currentSource()
        hasObservedAppliedSource = sourceBeforeApply == source
        lastAppliedSource = source
        lastAppliedAt = now()
        applySource(source)
        onApplied(source, key)
    }

    func inputChanged() {
        guard let key = currentKey, let source = currentSource() else { return }
        // Our own apply echoing back — the prompt echo or one of the delayed
        // settling duplicates — all report the source we just applied.
        if let last = lastAppliedSource, now() - lastAppliedAt < echoWindow {
            if source == last {
                hasObservedAppliedSource = true
                return
            }
            if !hasObservedAppliedSource, source == sourceBeforeApply {
                return
            }
        }
        lastAppliedSource = nil   // a genuine change supersedes any pending echo
        sourceBeforeApply = nil
        hasObservedAppliedSource = false
        store(source, namespace, key)
        onSaved(source, key)
    }

    func reset() {
        currentKey = nil
        lastAppliedSource = nil
        sourceBeforeApply = nil
        hasObservedAppliedSource = false
    }
}
