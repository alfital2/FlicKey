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
    private var browserName: String?
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

    func start() {
        inputMonitor.onChange = { [weak self] in
            self?.core?.inputChanged()
            self?.onSiteChange?()
        }
        inputMonitor.start()
    }

    // MARK: - Browser lifecycle (driven by AppWatcher)

    func browserActivated(_ app: NSRunningApplication) {
        let name = app.localizedName
        if name != browserName {
            browserName = name
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
        pollTimer.start()
        startHints(pid: app.processIdentifier)
        poll()   // immediate, so activation doesn't wait a whole interval
    }

    func leftBrowser() {
        pollTimer.stop()
        stopHints()
        browserName = nil
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
            titleHint?.onHint = { [weak self] in self?.probeSoon() }
            hintedPID = pid
        }
        titleHint?.start()
        inputHint.onHint = { [weak self] in self?.probeSoon() }
        inputHint.start()
    }

    private func stopHints() {
        titleHint?.stop()
        inputHint.stop()
        pendingProbe?.cancel()
        pendingProbe = nil
    }

    private func probeSoon() {
        pendingProbe?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.poll() }
        pendingProbe = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeDelay, execute: work)
    }

    // MARK: - Polling

    // A blank/new tab is remembered under one reserved key shared across browsers.
    // The parentheses make it un-collidable with any real DNS host, and readable
    // if someone inspects the stored memory.
    static let newTabKey = "(new-tab)"
    static let newTabDisplayName = "New Tab"

    private func poll() {
        guard let browserName, let core else { return }
        let key: String
        switch BrowserURLReader.state(forBrowserNamed: browserName) {
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
            return
        }
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
