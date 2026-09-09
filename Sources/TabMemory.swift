import AppKit

// Per-site input-language memory for browsers (Phase 5).
//
//   • While on a browser tab, when the input source changes → save {domain: language}.
//   • Switch to a known domain → apply its language immediately.
//   • Switch to an unknown domain → do nothing.
//   • Change the input on a known domain → overwrite it.
//
// The decision logic lives in the shared ConversationMemoryCore (the same engine
// the Teams per-conversation feature uses); TabMemory supplies the browser's I/O:
// the "key" is the active tab's domain (via BrowserURLReader) and persistence is
// SiteMemoryStore (unchanged on-disk location).
//
// Tab switches are detected by POLLING the frontmost browser's active tab,
// accelerated by event hints. An earlier design relied on the AX title-change
// observer ALONE and proved unreliable in real-world setups: it missed switches
// (fired sparsely) and fired at moments when the read momentarily resolved to a
// background window, so the remembered site lagged or stuck on the wrong tab.
// Polling reads the active tab at a stable moment, every time, and stays the
// authoritative backstop; AX title changes and switch-shaped input events (see
// DetectionHints) merely trigger an early probe so the common case lands in
// ~100ms instead of a poll interval. A missed or spurious hint costs nothing:
// probes go through the same poll() and dedup on core.currentKey. The core is
// unit-tested.
final class TabMemory {

    private let inputMonitor = InputSourceMonitor()
    private var browserTarget: BrowserTarget?
    private var core: ConversationMemoryCore?

    // Re-read the active tab this often while a browser is frontmost: snappy
    // enough that the layout follows a tab switch promptly, light enough to not
    // hammer AppleScript. This is the reliability backstop; the hints below make
    // the common case much faster.
    private static let pollInterval: TimeInterval = 0.7
    private lazy var pollTimer = PollTimer(interval: Self.pollInterval) { [weak self] in self?.poll() }

    // Event hints (see DetectionHints): an AX title change or a switch-shaped
    // input event triggers one probe ~80ms later, so a tab switch is detected
    // near-instantly instead of on the next poll tick. The delay lets the browser
    // finish updating its active tab before we read it; repeat hints inside the
    // window coalesce into a single probe.
    private static let probeDelay: TimeInterval = 0.08
    private var titleHint: TitleChangeHint?
    private var hintedPID: pid_t = 0
    private let inputHint = InputActivityHint()
    private var pendingProbe: DispatchWorkItem?

    // Firefox builds its native AX tree asynchronously after the first AXRole
    // request. A cold read can therefore fail even though the next read tens of
    // milliseconds later succeeds. Retry rapidly for one short, bounded burst;
    // the 700ms poll remains the long-term backstop.
    private var readinessRetry = AccessibilityReadinessRetrySchedule()
    private var pendingReadinessRetry: DispatchWorkItem?

    func start() {
        inputMonitor.onChange = { [weak self] in
            self?.core?.inputChanged()
            self?.onSiteChange?()
        }
        inputMonitor.start()
    }

    // MARK: - Browser lifecycle (driven by AppWatcher)

    func browserActivated(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return }
        let target = BrowserTarget(name: app.localizedName ?? bundleID,
                                   bundleID: bundleID,
                                   pid: app.processIdentifier)
        if let prior = browserTarget, prior.pid != target.pid {
            AccessibilityURLReader.forget(pid: prior.pid)
        }
        if target.bundleID != browserTarget?.bundleID {
            // Browser memory stays in SiteMemoryStore (keyed by bare domain);
            // inject it so existing per-site data is preserved.
            core = ConversationMemoryCore(
                namespace: "site",
                lookup: { _, domain in SiteMemoryStore.sourceID(for: domain) },
                store: { source, _, domain in SiteMemoryStore.set(source, for: domain) },
                onApplied: { source, domain in
                    SwitchStats.record(.siteSwitch)
                    Diag.log(.memoryApplied(scope: "site", keyHash: DiagnosticHash.token(domain), source: source)) },
                onSaved: { source, domain in
                    Diag.log(.memorySaved(scope: "site", keyHash: DiagnosticHash.token(domain), source: source)) })
        }
        browserTarget = target
        resetReadinessRetry()
        pollTimer.start()
        startHints(pid: app.processIdentifier)
        poll()   // immediate, so activation doesn't wait a whole interval
    }

    func leftBrowser() {
        pollTimer.stop()
        stopHints()
        resetReadinessRetry()
        if let target = browserTarget { AccessibilityURLReader.forget(pid: target.pid) }
        browserTarget = nil
        core?.reset()
        core = nil
        onSiteChange?()
    }

    // MARK: - Event hints

    private func startHints(pid: pid_t) {
        guard DetectionHints.isEnabled else { return }
        if pid != hintedPID {
            titleHint?.stop()
            titleHint = TitleChangeHint(pid: pid)
            titleHint?.onHint = { [weak self] in
                AccessibilityURLReader.clear(pid: pid)
                self?.resetReadinessRetry()
                self?.probeSoon()
            }
            hintedPID = pid
        }
        titleHint?.start()
        inputHint.onHint = { [weak self] in
            // Gecko can leave the prior tab's AXWebArea alive after a tab click
            // or keyboard shortcut. A probe against that cached object can read
            // the old URL successfully forever. Switch-shaped input is direct
            // evidence that the selected page may have changed, so rediscover
            // the web area before the accelerated probe.
            AccessibilityURLReader.clear(pid: pid)
            self?.resetReadinessRetry()
            self?.probeSoon()
        }
        inputHint.start()
    }

    private func stopHints() {
        titleHint?.stop()
        inputHint.stop()
        pendingProbe?.cancel()
        pendingProbe = nil
        resetReadinessRetry()
    }

    private func probeSoon() {
        pendingProbe?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.poll() }
        pendingProbe = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeDelay, execute: work)
    }

    private func scheduleReadinessRetry() {
        guard pendingReadinessRetry == nil,
              let delay = readinessRetry.takeNextDelay() else { return }
        if DebugLog.enabled {
            DebugLog.recovery.notice("browser AX not ready; rapid retry \(self.readinessRetry.attemptsIssued, privacy: .public)")
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReadinessRetry = nil
            self.poll()
        }
        pendingReadinessRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resetReadinessRetry() {
        pendingReadinessRetry?.cancel()
        pendingReadinessRetry = nil
        readinessRetry.reset()
    }

    private func markBrowserReady() {
        // The observer may have been created during Gecko's cold-start window
        // while its individual AX notification registrations were still being
        // rejected. `start()` is idempotent and retries only missing
        // registrations, so proving the tree readable is the right point to arm
        // tab-change events without requiring an app focus cycle.
        titleHint?.start()
        let attempts = readinessRetry.attemptsIssued
        resetReadinessRetry()
        if attempts > 0, DebugLog.enabled {
            DebugLog.recovery.notice("browser AX ready after \(attempts, privacy: .public) rapid retries")
        }
    }

    // MARK: - Polling

    // A blank/new tab is remembered under one reserved key shared across browsers.
    // The parentheses make it un-collidable with any real DNS host, and readable
    // if someone inspects the stored memory.
    static let newTabKey = "(new-tab)"
    static let newTabDisplayName = "New Tab"

    private func poll() {
        guard let browserTarget, let core else { return }
        let key: String
        switch BrowserURLReader.state(for: browserTarget) {
        case .site(let domain):
            key = domain
        case .newTab:
            // A fresh tab waiting for input: apply the user's new-tab language
            // (e.g. English for a Hebrew speaker who searches in English) instead
            // of inheriting the previous site's layout.
            key = Self.newTabKey
        case .unreadable:
            // Transient failure / unsupported browser / an untracked internal
            // page: keep the prior tab rather than clearing it.
            if BrowserURLReader.usesAccessibility(for: browserTarget) {
                scheduleReadinessRetry()
            }
            return
        }
        markBrowserReady()
        guard key != core.currentKey else { return }   // tab unchanged since last poll
        // The tab changed: log a short irreversible token of the key (never the
        // domain itself) + whether we have a remembered layout for it. Only on
        // change, so it doesn't spam.
        Diag.log(.siteResolved(domainHash: DiagnosticHash.token(key),
                               hadMemory: SiteMemoryStore.sourceID(for: key) != nil))
        core.enter(key: key)
        onSiteChange?()
    }

    // MARK: - Menu support

    var onSiteChange: (() -> Void)?
    var activeSiteDomain: String? { core?.currentKey }

    // The current tab's name for display: "New Tab" for the reserved blank-tab
    // key, the domain otherwise. nil when no browser tab is active.
    var activeSiteDisplayName: String? {
        guard let key = core?.currentKey else { return nil }
        return key == Self.newTabKey ? Self.newTabDisplayName : key
    }

    func pinnedSourceID() -> String? {
        guard let domain = core?.currentKey else { return nil }
        return SiteMemoryStore.sourceID(for: domain)
    }

    // Manual override from the menu (and apply now), or nil to forget the site.
    func pin(_ sourceID: String?) {
        guard let domain = core?.currentKey else { return }
        if let sourceID {
            SiteMemoryStore.set(sourceID, for: domain)
            InputSourceManager.switchTo(sourceID: sourceID)
        } else {
            SiteMemoryStore.clear(domain)
        }
        onSiteChange?()
    }
}
