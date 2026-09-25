import AppKit

// Watches frontmost-app changes and forces a keyboard input language for
// specific apps (ports the Hammerspoon app-watcher behavior). Browsers are
// not forced here — they're handed to TabMemory (Phase 5) for per-tab memory.
final class AppWatcher {

    private enum LearningMode {
        case undefined
        case persistent
    }

    private struct LearningTarget {
        let app: AppRule
        let pid: pid_t
        let mode: LearningMode
    }

    private struct ForcedActivation {
        let token: UUID
        let sourceID: String
        let pid: pid_t
        let expiresAt: TimeInterval
    }

    // Injected in Phase 5 to hand browser activations to TabMemory.
    var onBrowserActivated: ((NSRunningApplication) -> Void)?
    // Called when a non-browser (or EN/HE-forced) app becomes active, so
    // TabMemory can stop monitoring the browser it was watching.
    var onLeftBrowser: (() -> Void)?
    // Called when an app with a per-conversation provider (e.g. Teams) becomes
    // active, so AppConversationMemory can track its conversations.
    var onConversationApp: ((NSRunningApplication) -> Void)?

    private var observer: NSObjectProtocol?
    private let inputMonitor = InputSourceMonitor()
    private var learningTarget: LearningTarget?
    // macOS can finish a previous app's layout selection after this app's
    // activation. Keep a short, cancellable handoff for a fixed rule.
    private var forcedActivation: ForcedActivation?

    func start() {
        inputMonitor.onChange = { [weak self] in
            // Capture both halves of the event before hopping to the main queue.
            // Otherwise an app activation between notification delivery and the
            // queued callback could attribute the old app's change to the new one.
            let sourceID = InputSourceManager.currentSourceID()
            let frontmost = NSWorkspace.shared.frontmostApplication
            let pid = frontmost?.processIdentifier
            let bundleID = frontmost?.bundleIdentifier
            DispatchQueue.main.async {
                self?.inputSourceChanged(sourceID: sourceID,
                                         frontmostPID: pid,
                                         frontmostBundleID: bundleID)
            }
        }
        inputMonitor.start()

        let nc = NSWorkspace.shared.notificationCenter
        observer = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            self?.handle(app)
        }

        // Apply the rule for whatever app is already frontmost at launch.
        if let front = NSWorkspace.shared.frontmostApplication {
            handle(front)
        }
    }

    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        inputMonitor.stop()
        learningTarget = nil
        forcedActivation = nil
    }

    // Routes an app to its input rule. Called for normal activations (the
    // NSWorkspace observer above) and, for non-activating panels that never post
    // an activation (e.g. Ghostty's quick terminal), by FocusWatcher — so both
    // paths share the exact same routing + controller-release behavior.
    func handle(_ app: NSRunningApplication) {
        // Ignore our own activation (e.g. opening the menu bar) so it doesn't
        // count as "left the browser" and clear the current site.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }

        let matchedApp = AppRules.appRuleForVisit(
            bundleID: app.bundleIdentifier,
            name: app.localizedName,
            sourceID: InputSourceManager.currentSourceID())
        let providerExists = ConversationProviderRegistry.provider(forBundleID: app.bundleIdentifier) != nil
        let rule = matchedApp?.rule ?? (providerExists ? .auto : nil)
        let kind = matchedApp?.kind ?? (providerExists ? .conversation : nil)
        let decision = AppRouting.decide(rule: rule, kind: kind)
        let bundleID = app.bundleIdentifier ?? "?"
        Diag.log(.appActivated(bundleID: bundleID))
        Diag.log(.routingDecision(bundleID: bundleID, decision: decision.diagKind))
        forcedActivation = nil

        switch decision {
        case .force(let id):
            learningTarget = nil
            onLeftBrowser?()                 // releases both auto-controllers
            let activation = ForcedActivation(
                token: UUID(), sourceID: id, pid: app.processIdentifier,
                expiresAt: ProcessInfo.processInfo.systemUptime + 0.9)
            forcedActivation = activation
            apply(id, to: app)
            // Notifications catch most late switches. These checks also catch
            // a switch that lands without a delivered notification.
            for delay in [0.15, 0.4, 0.75] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.reassertForcedLayout(for: activation)
                }
            }
        case .rememberApp:
            onLeftBrowser?()
            guard let matchedApp else { learningTarget = nil; return }
            learningTarget = LearningTarget(app: matchedApp, pid: app.processIdentifier,
                                            mode: .persistent)
            if let remembered = AppLastUsedInputStore.sourceID(for: matchedApp.memoryKey) {
                apply(remembered, to: app)
            } else if let current = InputSourceManager.currentSourceID() {
                AppLastUsedInputStore.set(current, for: matchedApp.memoryKey)
            }
        case .conversation:
            learningTarget = nil
            onConversationApp?(app)
        case .browser:
            learningTarget = nil
            onBrowserActivated?(app)
        case .leaveAsIs:
            if let matchedApp, matchedApp.learnsAppPreference {
                learningTarget = LearningTarget(app: matchedApp, pid: app.processIdentifier,
                                                mode: .undefined)
            } else {
                learningTarget = nil
            }
            onLeftBrowser?()                 // no rule → leave the input source as-is
        }
    }

    private func apply(_ sourceID: String, to app: NSRunningApplication) {
        Diag.log(.layoutSwitch(expected: sourceID, applied: sourceID))
        // Recorded in the shared ledger so neither this watcher nor the
        // site/conversation memories learn its echoes as a user choice.
        ProgrammaticSwitches.apply(sourceID)
        SwitchStats.record(.appSwitch)
    }

    private func inputSourceChanged(sourceID: String?,
                                    frontmostPID: pid_t?,
                                    frontmostBundleID: String?) {
        guard let sourceID else { return }
        // Correct the actual selected source before classifying this
        // notification as an echo. A delayed prior-app change can be an echo
        // of a different owner and still override this app's fixed rule.
        if let forced = forcedActivation, frontmostPID == forced.pid {
            reassertForcedLayout(for: forced)
        }
        // Any recent FlicKey switch, including one made for the app the user
        // just left, echoes here after the next app is already frontmost.
        if ProgrammaticSwitches.isEcho(sourceID) { return }

        guard let target = learningTarget,
              frontmostPID == target.pid,
              frontmostBundleID?.caseInsensitiveCompare(target.app.bundleID) == .orderedSame
        else { return }

        switch target.mode {
        case .undefined:
            AppRules.rememberSource(sourceID, for: target.app)
        case .persistent:
            AppLastUsedInputStore.set(sourceID, for: target.app.memoryKey)
        }
    }

    private func reassertForcedLayout(for activation: ForcedActivation) {
        guard forcedActivation?.token == activation.token,
              ProcessInfo.processInfo.systemUptime < activation.expiresAt,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == activation.pid,
              InputSourceManager.currentSourceID() != activation.sourceID
        else { return }

        Diag.log(.layoutSwitch(expected: activation.sourceID, applied: activation.sourceID))
        ProgrammaticSwitches.apply(activation.sourceID)
    }
}

private extension AppRouting.Decision {
    // Categorical tag for the diagnostics trail.
    var diagKind: RoutingKind {
        switch self {
        case .force:       return .force
        case .rememberApp: return .force
        case .conversation: return .conversation
        case .browser:     return .browser
        case .leaveAsIs:   return .leaveAsIs
        }
    }
}
