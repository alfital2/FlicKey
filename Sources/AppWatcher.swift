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

    private struct IgnoredProgrammaticChange {
        let sourceID: String
        let pid: pid_t
        let bundleID: String
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
    // A layout forced by this watcher also emits the same system notification
    // as a human switch. Consume that notification so a rapid activation of a
    // different, undefined app cannot learn our delayed programmatic switch.
    private var programmaticChangeToIgnore: IgnoredProgrammaticChange?

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

        switch decision {
        case .force(let id):
            learningTarget = nil
            onLeftBrowser?()                 // releases both auto-controllers
            apply(id, to: app)
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
        if InputSourceManager.currentSourceID() != sourceID {
            programmaticChangeToIgnore = IgnoredProgrammaticChange(
                sourceID: sourceID,
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier ?? "",
                expiresAt: ProcessInfo.processInfo.systemUptime + 1.0)
            InputSourceManager.switchTo(sourceID: sourceID)
        }
        SwitchStats.record(.appSwitch)
    }

    private func inputSourceChanged(sourceID: String?,
                                    frontmostPID: pid_t?,
                                    frontmostBundleID: String?) {
        guard let sourceID else { return }

        if let ignored = programmaticChangeToIgnore,
           ignored.sourceID == sourceID,
           ignored.pid == frontmostPID,
           ignored.bundleID.caseInsensitiveCompare(frontmostBundleID ?? "") == .orderedSame,
           ProcessInfo.processInfo.systemUptime <= ignored.expiresAt {
            programmaticChangeToIgnore = nil
            return
        }
        // A stale ignore token must not swallow a later genuine user change to
        // another source.
        programmaticChangeToIgnore = nil

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
