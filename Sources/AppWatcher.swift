import AppKit

// Watches frontmost-app changes and forces a keyboard input language for
// specific apps (ports the Hammerspoon app-watcher behavior). Browsers are
// not forced here — they're handed to TabMemory (Phase 5) for per-tab memory.
final class AppWatcher {

    private struct LearningTarget {
        let app: AppRule
        let pid: pid_t
    }

    private struct IgnoredProgrammaticChange {
        let sourceID: String
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
        let rule = matchedApp?.rule
        let isConversationApp = ConversationProviderRegistry.provider(forBundleID: app.bundleIdentifier) != nil

        // An ordinary app participates only when it is present in AppRules
        // (manually added, imported, or retained after learning). Browser/chat
        // rows must never be learned app-wide.
        if let matchedApp, matchedApp.learnsAppPreference {
            learningTarget = LearningTarget(app: matchedApp, pid: app.processIdentifier)
        } else {
            learningTarget = nil
        }

        let decision = AppRouting.decide(rule: rule, isConversationApp: isConversationApp)
        let bundleID = app.bundleIdentifier ?? "?"
        Diag.log(.appActivated(bundleID: bundleID))
        Diag.log(.routingDecision(bundleID: bundleID, decision: decision.diagKind))

        switch decision {
        case .force(let id):
            Diag.log(.layoutSwitch(expected: id, applied: id))
            onLeftBrowser?()                 // releases both auto-controllers
            if InputSourceManager.currentSourceID() != id {
                programmaticChangeToIgnore = IgnoredProgrammaticChange(
                    sourceID: id,
                    expiresAt: ProcessInfo.processInfo.systemUptime + 1.0)
            }
            InputSourceManager.switchTo(sourceID: id)
            SwitchStats.record(.appSwitch)
        case .conversation:
            onConversationApp?(app)          // e.g. Teams → per-conversation
        case .browser:
            onBrowserActivated?(app)         // browser → per-site memory
        case .leaveAsIs:
            onLeftBrowser?()                 // no rule → leave the input source as-is
        }
    }

    private func inputSourceChanged(sourceID: String?,
                                    frontmostPID: pid_t?,
                                    frontmostBundleID: String?) {
        guard let sourceID else { return }

        if let ignored = programmaticChangeToIgnore,
           ignored.sourceID == sourceID,
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

        AppRules.rememberSource(sourceID, for: target.app)
    }
}

private extension AppRouting.Decision {
    // Categorical tag for the diagnostics trail.
    var diagKind: RoutingKind {
        switch self {
        case .force:       return .force
        case .conversation: return .conversation
        case .browser:     return .browser
        case .leaveAsIs:   return .leaveAsIs
        }
    }
}
