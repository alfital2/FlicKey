import AppKit

// Watches frontmost-app changes and forces a keyboard input language for
// specific apps (ports the Hammerspoon app-watcher behavior). Browsers are
// not forced here — they're handed to TabMemory (Phase 5) for per-tab memory.
final class AppWatcher {

    // Injected in Phase 5 to hand browser activations to TabMemory.
    var onBrowserActivated: ((NSRunningApplication) -> Void)?
    // Called when a non-browser (or EN/HE-forced) app becomes active, so
    // TabMemory can stop monitoring the browser it was watching.
    var onLeftBrowser: (() -> Void)?
    // Called when an app with a per-conversation provider (e.g. Teams) becomes
    // active, so AppConversationMemory can track its conversations.
    var onConversationApp: ((NSRunningApplication) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
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

        let name = AppRules.normalizedName(app.localizedName)
        let rule = name.isEmpty ? nil : AppRules.rule(forNormalizedName: name)
        let isConversationApp = ConversationProviderRegistry.provider(forBundleID: app.bundleIdentifier) != nil

        let decision = AppRouting.decide(rule: rule, isConversationApp: isConversationApp)
        let bundleID = app.bundleIdentifier ?? "?"
        Diag.log(.appActivated(bundleID: bundleID))
        Diag.log(.routingDecision(bundleID: bundleID, decision: decision.diagKind))

        switch decision {
        case .force(let id):
            Diag.log(.layoutSwitch(expected: id, applied: id))
            onLeftBrowser?()                 // releases both auto-controllers
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
