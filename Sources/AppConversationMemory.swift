import AppKit

// Per-conversation input-language memory for non-browser apps, driven by a
// ConversationProvider. The Accessibility/polling wiring lives here; the decision
// logic lives in ConversationMemoryCore (unit-tested separately).
//
// Structurally a sibling of TabMemory (the browser per-site controller), and it
// detects conversation switches the same way: POLLING the focused window title
// while the app is frontmost, accelerated by event hints (see DetectionHints).
// Polling stays authoritative because for Chromium/WebView2 apps (Microsoft
// Teams) the event model alone is unreliable: Teams tears its Accessibility tree
// down when backgrounded (~5 min) and never rebuilds it on reveal, so
// kAXTitleChanged goes silent and reads return empty for the rest of the session
// (confirmed by field telemetry). Poll + toggle-recovery (ChromiumAX.forceRebuild)
// survives and recovers from that; hints only shave latency when events do fire.
//
// The two controllers are mutually exclusive: AppWatcher/AppDelegate release one
// when the other activates, so the "save current source on every input change"
// shortcut is safe — only the active controller ever has a live key.
final class AppConversationMemory {

    private let inputMonitor = InputSourceMonitor()
    private var provider: ConversationProvider?
    private var core: ConversationMemoryCore?
    private var pid: pid_t = 0

    // Snappy enough that the layout follows a chat switch promptly, light enough
    // that the AX reads are negligible. This is the reliability backstop (it is
    // what survives the Teams AX-tree teardown); the hints below make the common
    // case much faster.
    private static let pollInterval: TimeInterval = 0.4
    private lazy var pollTimer = PollTimer(interval: Self.pollInterval) { [weak self] in self?.poll() }

    // Event hints (see DetectionHints): an AX title change or a switch-shaped
    // input event (chat click, ⌘K, ⌘1-9) schedules a short burst of probes. A
    // burst, not a single read, because Teams retitles in stages: captured timing
    // shows the new title often lands only 100 to 400ms after the click, so one
    // early read sees the old title and the switch would wait for the next poll
    // tick anyway. Each probe is one cheap AX read; a fresh hint restarts the
    // burst, and probes dedup through core.currentKey like any poll.
    private static let probeBurstSchedule: [TimeInterval] = [0.08, 0.20, 0.35, 0.55]
    private var titleHint: TitleChangeHint?
    private let inputHint = InputActivityHint()
    private var burstProbes: [DispatchWorkItem] = []

    // Recovery bookkeeping: after N consecutive unreadable polls (AX tree torn
    // down) we toggle the app's accessibility flag to force a rebuild — debounced
    // so we don't toggle every tick while it rebuilds (~2s).
    private var consecutiveUnreadable = 0
    private static let unreadableThreshold = 2
    private var lastRecoveryAt: TimeInterval = 0
    private static let recoveryDebounce: TimeInterval = 4

    func start() {
        inputMonitor.onChange = { [weak self] in self?.core?.inputChanged() }
        inputMonitor.start()
    }

    // MARK: - App lifecycle (driven by AppWatcher)

    func appActivated(_ app: NSRunningApplication) {
        guard let provider = ConversationProviderRegistry.provider(forBundleID: app.bundleIdentifier) else {
            leftApp()
            return
        }
        let newPID = app.processIdentifier
        if newPID != pid || self.provider == nil {
            pollTimer.stop()
            stopHints()
            pid = newPID
            self.provider = provider
            let ns = provider.namespace
            core = ConversationMemoryCore(
                namespace: ns,
                onApplied: { source, key in
                    SwitchStats.record(.chatSwitch)
                    Diag.log(.memoryApplied(scope: ns, keyHash: DiagnosticHash.token(key), source: source)) },
                onSaved: { source, key in
                    Diag.log(.memorySaved(scope: ns, keyHash: DiagnosticHash.token(key), source: source)) })
            ChromiumAX.enable(pid: newPID)   // prompt Teams to build its AX tree
        }
        // Returning to Teams after it was backgrounded is exactly when its AX tree
        // may be torn down. Read once; if it's unreadable, force a rebuild now
        // (a plain re-enable is a no-op — see ChromiumAX). Polling picks up the
        // rebuilt tree ~2s later.
        consecutiveUnreadable = 0
        if !refresh() { forceRecovery() }
        pollTimer.start()
        startHints()
    }

    func leftApp() {
        pollTimer.stop()
        stopHints()
        core?.reset()
        core = nil
        provider = nil
        pid = 0
        consecutiveUnreadable = 0
    }

    // MARK: - Event hints

    private func startHints() {
        guard DetectionHints.isEnabled, pid != 0 else { return }
        if titleHint == nil {
            titleHint = TitleChangeHint(pid: pid)
            titleHint?.onHint = { [weak self] in self?.probeSoon(source: "title") }
        }
        titleHint?.start()
        inputHint.onHint = { [weak self] in self?.probeSoon(source: "input") }
        inputHint.start()
    }

    private func stopHints() {
        titleHint?.stop()
        titleHint = nil   // pid-bound; recreated for the next app
        inputHint.stop()
        cancelBurst()
    }

    private func probeSoon(source: StaticString) {
        if DebugLog.enabled { DebugLog.event.notice("hint(\(source, privacy: .public)) → burst") }
        cancelBurst()
        for delay in Self.probeBurstSchedule {
            let work = DispatchWorkItem { [weak self] in self?.probe() }
            burstProbes.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelBurst() {
        burstProbes.forEach { $0.cancel() }
        burstProbes.removeAll()
    }

    // Hint-driven probe. Unlike poll(), a failed read here never feeds the
    // recovery counter: probes fire at event rate, and a read can be legitimately
    // unreadable for a beat mid retitle, so counting them would let one click
    // burst reach the threshold and tear the tree down (forceRebuild) exactly
    // when the app is healthy. Only the steady poll cadence is evidence of a
    // genuinely torn-down tree. A successful probe still clears the counter.
    private func probe() {
        let readable = refresh()
        if DebugLog.enabled { DebugLog.event.notice("probe → \(readable ? "readable" : "unreadable", privacy: .public)") }
        if readable { consecutiveUnreadable = 0 }
    }

    // MARK: - Polling

    private func poll() {
        if refresh() {
            consecutiveUnreadable = 0
        } else {
            consecutiveUnreadable += 1
            if consecutiveUnreadable == Self.unreadableThreshold {
                // Log once per unreadable episode (at the crossing, not every poll)
                // — the "Teams stopped remembering" signal, without spamming.
                Diag.log(.conversationUnreadable(namespace: provider?.namespace ?? "?"))
            }
            if consecutiveUnreadable >= Self.unreadableThreshold { forceRecovery() }
        }
    }

    // Toggle the app's accessibility flag false→true to force Chromium to rebuild
    // its torn-down AX tree. Debounced, and resets the unreadable counter to give
    // the async (~2s) rebuild time before we count failures again.
    private func forceRecovery() {
        guard pid != 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRecoveryAt > Self.recoveryDebounce else { return }
        lastRecoveryAt = now
        consecutiveUnreadable = 0
        ChromiumAX.forceRebuild(pid: pid)
    }

    // MARK: - Core wiring

    // Read the current conversation context from the provider (one cheap AX title
    // fetch, resolved fresh each call — no cached, staleable element) and hand it
    // to the decision core. Returns whether the context was READABLE (a real
    // conversation or a definite non-conversation); false = AX tree not ready.
    private func refresh() -> Bool {
        guard let provider, let core, pid != 0 else { return true }
        switch provider.context(pid: pid) {
        case .conversation(let key):
            // On a CHANGE of conversation, log a short irreversible token of the
            // chat identity (never the name) + whether we have a remembered layout
            // for it, so a stuck or mis-detected chat is visible in the trail.
            // Only on change, so repeated polls of the same chat don't spam.
            if key != core.currentKey {
                Diag.log(.conversationKeyResolved(
                    namespace: provider.namespace,
                    keyHash: DiagnosticHash.token(key),
                    hadMemory: ContextMemoryStore.sourceID(namespace: provider.namespace, key: key) != nil))
            }
            core.enter(key: key)
            return true
        case .notAConversation:
            core.enter(key: nil)
            return true
        case .unreadable:
            return false   // AX tree not ready / torn down — keep prior key
        }
    }
}
