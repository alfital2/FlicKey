import AppKit
import ApplicationServices

// Per-app Accessibility observer. Owns one AXObserver for a single app (create,
// addNotification, run-loop source; balanced in stop()/deinit; refcon via
// Unmanaged.passUnretained). Reports two things:
//   onFocus:        the app's focused element or window changed, i.e. a (possibly
//                   non-activating) panel grabbed the keyboard.
//   onMaybeDismiss: a UI element was destroyed. FocusWatcher then checks
//                   ownsSystemKeyboardFocus() to tell a real panel dismiss
//                   (keyboard returned to the underlying app) from element churn
//                   while the panel is still open.
final class AppFocusObserver {

    var onFocus: (() -> Void)?
    var onMaybeDismiss: (() -> Void)?

    private let pid: pid_t
    private let appElement: AXUIElement
    private var observer: AXObserver?

    // A single summon posts these within a few ms; FocusWatcher coalesces them.
    private static let focusNotifications = [
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]
    // A non-activating panel posts NO focus/activation event when it is dismissed
    // — but it destroys its window, which fires this. (Verified for Ghostty's
    // quick terminal.)
    private static let dismissNotification = kAXUIElementDestroyedNotification

    init(pid: pid_t) {
        self.pid = pid
        self.appElement = AXUIElementCreateApplication(pid)
    }

    // Backstop: balance the AX registrations + run-loop source even if a caller
    // drops us without stop(), so the C callback can't fire into freed memory.
    deinit { stop() }

    func start() {
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<AppFocusObserver>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(notification as String)
        }

        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        observer = obs

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.focusNotifications {
            AXObserverAddNotification(obs, appElement, n as CFString, refcon)
        }
        AXObserverAddNotification(obs, appElement, Self.dismissNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    func stop() {
        guard let obs = observer else { return }
        for n in Self.focusNotifications {
            AXObserverRemoveNotification(obs, appElement, n as CFString)
        }
        AXObserverRemoveNotification(obs, appElement, Self.dismissNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = nil
    }

    // Does THIS app currently hold the SYSTEM-WIDE keyboard focus? A non-activating
    // panel that genuinely grabs the keyboard (Ghostty's quick terminal) becomes
    // the owner of the system-wide focused element even though the app never turns
    // frontmost. A backgrounded forced app that merely emits focus-changed AX noise
    // (e.g. WhatsApp firing an event while the user switches terminal tabs) does
    // NOT — the system focus still belongs to the real frontmost app. Used to keep
    // the not-frontmost force path from hijacking the frontmost app's input source.
    func ownsSystemKeyboardFocus() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let element = ref else { return false }
        // The focused-element attribute is always an AXUIElement; read its owner pid.
        let focused = element as! AXUIElement
        var owner: pid_t = 0
        guard AXUIElementGetPid(focused, &owner) == .success else { return false }
        return owner == pid
    }

    private func handle(_ notification: String) {
        if notification == Self.dismissNotification as String { onMaybeDismiss?() }
        else { onFocus?() }
    }
}

// Applies an app's input rule when it gains keyboard focus via a path that
// NSWorkspace.didActivateApplicationNotification misses — specifically
// non-activating panels such as Ghostty's quick terminal, which receive the
// keyboard without the app ever becoming frontmost — and RESTORES the underlying
// app's layout when that panel is dismissed.
//
// It observes the focused-element/window of every running app that has a FORCED
// source rule (the rule list drives the set, so it stays generic as the user adds
// apps), and routes a detected focus through AppWatcher's existing router
// (FocusWatcher.applyRule → AppWatcher.handle). Reusing handle is deliberate: the
// forced path also releases the per-site/per-conversation controllers before
// switching, and we must not duplicate (or skip) that.
//
// Restore on dismiss: a non-activating panel posts no event when closed and the
// app it overlaid was frontmost the whole time (so no activation fires for it
// either). We detect the close via kAXUIElementDestroyed on the panel's app,
// gated by the app no longer owning the system keyboard focus (so element churn
// while the panel is open — e.g. terminal output — doesn't trigger it), then
// re-apply whatever app is now frontmost. (If a panel host does NOT destroy a
// UI element on dismiss, the restore simply doesn't fire — no worse than before.)
//
// Normal activations still go through AppWatcher as before; this only adds the
// missing event sources. All work is main-thread.
final class FocusWatcher {

    // Wired (in AppDelegate) to AppWatcher.handle, so a focus- or dismiss-driven
    // switch takes the identical route as a normal activation.
    var applyRule: ((NSRunningApplication) -> Void)?

    private var observers: [pid_t: AppFocusObserver] = [:]
    private var lastForcedAt: [pid_t: TimeInterval] = [:]
    // Tracks apps whose non-activating panel currently holds the keyboard, so the
    // dismiss can be recognized and the underlying app restored.
    private var panelSession = PanelSession()
    private var workspaceTokens: [NSObjectProtocol] = []
    private var rulesToken: NSObjectProtocol?

    // For FocusGate's switch-away guard: the most recent app activation.
    private var lastActivatedAt: TimeInterval?
    private var lastActivatedPID: pid_t?

    // MARK: - Lifecycle

    func start() {
        let ws = NSWorkspace.shared.notificationCenter

        // A forced app launching after us → start watching it.
        observeWorkspace(ws, NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            guard let self, self.shouldObserve(app) else { return }
            self.attach(app)
        }
        // App quit → drop its observer (its pid is dead).
        observeWorkspace(ws, NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.detach(app.processIdentifier)
        }
        // Record activations so the gate can tell a real app switch (which
        // AppWatcher already handles) from a non-activating panel summon, which
        // posts no activation.
        observeWorkspace(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.lastActivatedAt = ProcessInfo.processInfo.systemUptime
            self?.lastActivatedPID = app.processIdentifier
        }
        // The user edited the app list → re-sync which apps we observe.
        rulesToken = NotificationCenter.default.addObserver(
            forName: .appRulesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }

        sync()   // attach to forced apps already running at launch
    }

    func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { ws.removeObserver($0) }
        workspaceTokens.removeAll()
        if let rulesToken { NotificationCenter.default.removeObserver(rulesToken) }
        rulesToken = nil
        observers.values.forEach { $0.stop() }
        observers.removeAll()
        lastForcedAt.removeAll()
        panelSession = PanelSession()
    }

    // MARK: - Observer set, kept in sync with the forced-rule list

    // The single predicate for "FocusWatcher should watch this app": it isn't us,
    // and it currently resolves to a forced input source. Activation policy is
    // intentionally NOT a factor — forced apps can be agents/menu-bar apps
    // (LSUIElement launchers, quick-terminal hosts), which are exactly the kind
    // that summon non-activating panels. Used by BOTH didLaunch and sync() so the
    // membership test can never disagree between the two.
    // System overlays that grab the keyboard as a NON-ACTIVATING panel, can change the
    // input source WITHOUT owning a forced rule (a ⇧⇧ conversion or auto-switch typed into
    // Spotlight), and post NO activation when dismissed — so a forced app underneath never
    // gets its rule reasserted on return (BUG-B). Observe them for the SAME reason as forced
    // apps: their kAXUIElementDestroyed dismiss re-applies whatever app is now frontmost.
    // applyRule(overlay) is itself a no-op (the overlay has no rule); the whole value is the
    // dismiss → restore edge. If a host doesn't post these events the observer is simply
    // inert — no worse than today.
    private static let overlayHostBundleIDs: Set<String> = ["com.apple.Spotlight"]

    private func shouldObserve(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        if AppRules.forcedSourceID(forAppNamed: app.localizedName) != nil { return true }
        return Self.overlayHostBundleIDs.contains(app.bundleIdentifier ?? "")
    }

    private func sync() {
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            let pid = app.processIdentifier
            if shouldObserve(app) {
                if observers[pid] == nil { attach(app) }
            } else if observers[pid] != nil {
                detach(pid)
            }
        }

        // Drop observers for apps that are no longer running. Build the live-pid
        // set from the SAME unfiltered list used above, and snapshot the keys —
        // detach() mutates `observers`, which is illegal to do mid-iteration.
        let runningPIDs = Set(running.map { $0.processIdentifier })
        for pid in Array(observers.keys) where !runningPIDs.contains(pid) {
            detach(pid)
        }
    }

    private func attach(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        let observer = AppFocusObserver(pid: pid)
        observer.onFocus = { [weak self] in self?.focusChanged(app) }
        observer.onMaybeDismiss = { [weak self] in self?.maybeDismiss(app) }
        observer.start()
        observers[pid] = observer
    }

    private func detach(_ pid: pid_t) {
        observers[pid]?.stop()
        observers[pid] = nil
        lastForcedAt[pid] = nil
        panelSession.forget(pid: pid)
    }

    // MARK: - Focus / dismiss events

    private func focusChanged(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let now = ProcessInfo.processInfo.systemUptime
        let sinceForce = lastForcedAt[pid].map { now - $0 } ?? .infinity
        let sinceActivation = lastActivatedAt.map { now - $0 } ?? .infinity

        guard FocusGate.shouldForce(
            sinceLastForce: sinceForce,
            sinceActivation: sinceActivation,
            activationWasSelf: lastActivatedPID == pid
        ) else { return }

        // Only assert a layout if this app actually holds the system keyboard
        // focus right now. AppWatcher already forces on real activations, so this
        // supplementary focus path exists ONLY for keyboard grabs that post no
        // activation (non-activating panels). The keyboard-ownership test rejects
        // the two ways a focus event here is spurious:
        //   (a) a backgrounded forced app emitting focus-changed AX noise while the
        //       user works elsewhere (e.g. WhatsApp during a terminal tab-switch), and
        //   (b) a FRONTMOST app whose keyboard was taken by a non-activating panel
        //       overlaying it (e.g. Terminal under Ghostty's quick terminal) — its
        //       own focus events must NOT steal the keyboard back from the panel.
        // If ownership is momentarily ambiguous for a genuine activation, AppWatcher
        // already forced it via didActivate, so skipping here is at worst a no-op.
        guard observers[pid]?.ownsSystemKeyboardFocus() ?? false else { return }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid

        lastForcedAt[pid] = now
        // A non-activating panel that grabbed the keyboard opens a session so we can
        // restore the underlying app when that panel is dismissed.
        panelSession.forced(pid: pid, appWasFrontmost: isFrontmost)
        if !isFrontmost { Diag.log(.panelEvent(kind: .shown)) }
        applyRule?(app)
    }

    private func maybeDismiss(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        // Cheap pre-check: skip the Accessibility read unless this app has an open
        // panel that a destroy could be dismissing.
        guard panelSession.hasOpenPanel(pid: pid), let observer = observers[pid] else { return }
        // A real dismiss returns the keyboard to the underlying app, so the panel's
        // app stops owning the system keyboard focus. Keyboard ownership is the right
        // signal because it holds even when a regular window of the same app keeps its
        // own focused element alive: a forced app with both a quick-term panel and a
        // normal window open would otherwise never look dismissed. Element churn while
        // the panel is still open keeps keyboard ownership, so it correctly does not
        // count as a dismiss (we don't switch the layout out from under the user
        // mid-typing).
        guard panelSession.destroyed(pid: pid, keyboardFocusLost: !observer.ownsSystemKeyboardFocus())
        else { return }

        // No activation fires for the underlying app on dismiss, so re-apply
        // whatever is frontmost now (the app the panel overlaid).
        Diag.log(.panelEvent(kind: .dismissed))
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != pid {
            applyRule?(front)
        }
    }

    // MARK: - Helpers

    private func observeWorkspace(_ nc: NotificationCenter, _ name: Notification.Name,
                                  _ body: @escaping (NSRunningApplication) -> Void) {
        let token = nc.addObserver(forName: name, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            body(app)
        }
        workspaceTokens.append(token)
    }
}
