import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController?
    private let hotkeyManager = HotkeyManager()
    private let appWatcher = AppWatcher()
    private let focusWatcher = FocusWatcher()
    private let browserCatalogObserver = BrowserCatalogObserver()
    private let tabMemory = TabMemory()
    private let conversationMemory = AppConversationMemory()
    private let layoutCue = LayoutCueController()
    private let autoSwitch = AutoSwitchController()
    private let trialEnded = TrialEndedController()
    private var coreStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI tests: redirect all settings to a throwaway store BEFORE anything
        // reads it, so tests can't read or corrupt the user's real settings.
        if UITestMode.isActive {
            AppDefaults.useIsolatedStoreForUITests()
            // TrialManager/LicenseStore point at .uitest Keychain items in this
            // mode; clear the trial one so every UI-test run starts
            // deterministically on "day 1 of 7", unlicensed.
            TrialManager.reset()
        }
        // UI tests: seed per-site memory into the (isolated) store. Value form:
        //   "domain=sourceID;domain=sourceID"
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        Entitlement.applyDebugOverride(from: args)   // -simulateExpired etc.
        #endif
        if let i = args.firstIndex(of: "-uiTestSeedSites"), i + 1 < args.count {
            for pair in args[i + 1].split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { SiteMemoryStore.set(String(kv[1]), for: String(kv[0])) }
            }
        }
        // UI tests: seed per-app forced rules into the (isolated) store. Value
        // form: "AppName=sourceID;AppName=sourceID". Each app is added as a
        // custom entry (rules only resolve for listed apps) with an override.
        if let i = args.firstIndex(of: "-uiTestSeedAppRules"), i + 1 < args.count {
            for pair in args[i + 1].split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let name = String(kv[0])
                RulesStore.addCustomApp(CustomApp(name: name, bundleID: ""))
                RulesStore.set(String(kv[1]), forMatchKey: name.lowercased())
            }
        }

        statusBar = StatusBarController(tabMemory: tabMemory)
        browserCatalogObserver.start()
        requestAccessibilityPermission()

        // After a conversion, switch the keyboard layout to the converted
        // language so the user's next keystrokes are in the intended language.
        // The switch is FlicKey's own doing and the conversion already clicked,
        // so the layout-switch cue is muted for it.
        hotkeyManager.onConversion = { [weak self] targetSourceID in
            self?.layoutCue.suppress()
            InputSourceManager.switchTo(sourceID: targetSourceID)
        }
        // A ⇧⇧ right after an auto-switch undoes it instead of converting again.
        hotkeyManager.onUndoTrigger = { [weak self] in
            _ = self?.autoSwitch.handleUndoTrigger()
        }

        // Haptic/click cue on every effective layout change (app, tab, or
        // conversation switch — and manual ⌘Space). Cosmetic; runs regardless of
        // entitlement (there is simply nothing to cue when switching is gated).
        layoutCue.start()

        // Auto-correct (opt-in, default off): when two consecutive words are
        // confidently wrong-layout, fix them and switch the input source. Its own
        // switch mutes the layout cue, like a manual conversion.
        autoSwitch.suppressCue = { [weak self] in self?.layoutCue.suppress() }
        NotificationCenter.default.addObserver(
            forName: .autoSwitchSettingChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.coreStarted else { return }   // gated when trial expired
            AutoSwitchSettings.isEnabled ? self.autoSwitch.start() : self.autoSwitch.stop()
        }

        // Per-app automatic input switching. Browsers (AUTO) are handed to
        // TabMemory (per-website memory); apps with a conversation provider
        // (e.g. Teams) are handed to AppConversationMemory (per-conversation
        // memory). The two controllers are mutually exclusive: each activation
        // path releases the other so only one is ever tracking. (Started later,
        // gated by entitlement.)
        appWatcher.onBrowserActivated = { [weak self] app in
            self?.conversationMemory.leftApp()
            self?.tabMemory.browserActivated(app)
        }
        appWatcher.onConversationApp = { [weak self] app in
            self?.tabMemory.leftBrowser()
            self?.conversationMemory.appActivated(app)
        }
        appWatcher.onLeftBrowser = { [weak self] in
            self?.conversationMemory.leftApp()
            self?.tabMemory.leftBrowser()
        }

        // Non-activating panels (e.g. Ghostty's quick terminal) grab the
        // keyboard WITHOUT posting an app activation, so AppWatcher never sees
        // them and the forced layout isn't applied (nor restored on dismiss).
        // FocusWatcher watches the focused element of every forced-source app and
        // routes both the panel summon and its dismiss through the very same
        // AppWatcher router (so controller-release and switching stay identical to
        // a normal activation).
        focusWatcher.applyRule = { [weak self] app in
            self?.appWatcher.handle(app)
        }

        // In-app auto-update via Sparkle. Instantiating the updater starts it
        // and schedules the periodic background check; when a newer signed
        // release is available it offers to download, install, and relaunch -
        // all in-app, no browser. Skipped under UI tests so it can't pop a
        // dialog mid-run.
        if !UITestMode.isActive { _ = Updater.shared }

        // Entitlement gate: start the input-switching features only if the user
        // is entitled (licensed / grandfathered / in trial). A new user whose
        // trial has elapsed sees the trial-ended panel instead; buying re-enables
        // everything (via the .licenseChanged observer below).
        trialEnded.onEnterKey = { [weak self] in self?.statusBar?.presentSettingsForTesting() }
        NotificationCenter.default.addObserver(
            forName: .licenseChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshEntitlement()
        }
        // Persist the clock-rollback ratchet for every user (not only the nag
        // path), so setting the clock back can never revive or freeze a trial.
        if !UITestMode.isActive { TrialManager.persistRatchet() }

        refreshEntitlement()

        // The prior-use marker for the keychain-loss grandfather heuristic. Set
        // strictly AFTER the entitlement decision above, so a genuinely fresh
        // install's first load() ran with a clean defaults domain.
        if !UITestMode.isActive { TrialManager.markLaunchCompleted() }

        // One-time / periodic launch surfaces, for entitled users only (never on
        // the expired paywall), strictly one per launch. Precedence: the welcome
        // tour (fresh installs; their version IS the baseline, so it also consumes
        // the what's new note), then a what's new note for updating users, then
        // the blocked-words share offer.
        if Entitlement.current().coreEnabled {
            if WelcomeTourController.showIfNeeded() {
                if let note = WhatsNew.current { WhatsNewStore.seenVersion = note.version }
            } else if !WhatsNewController.showIfNeeded() {
                BlockedWordsSharingController.runIfNeeded()
            }
        }

        // Every 1000 switches, nudge non-licensed users with a friendly stat.
        NotificationCenter.default.addObserver(
            forName: .switchStatsChanged, object: nil, queue: .main) { _ in
            StatsNagController.checkAndNagIfNeeded()
        }

        // If licensed, re-check with Lemon Squeezy occasionally (throttled,
        // background, offline-tolerant) to honor refunds/revocations.
        LicenseStore.revalidateIfDue()

        // UI-test hook: open Settings on launch so the XCUITest suite doesn't
        // depend on clicking the (flaky to automate) menu-bar status item.
        if args.contains("-uiTestOpenSettings") {
            statusBar?.presentSettingsForTesting()
        }
    }

    // Start the gated features when entitled (once), or show the trial-ended
    // panel. Called at launch and whenever the license state changes.
    private func refreshEntitlement() {
        let entitlement = Entitlement.current()
        if entitlement.coreEnabled {
            trialEnded.dismiss()
            startCoreFeatures()
            runRemindersIfNeeded(for: entitlement)
        } else {
            trialEnded.present()
        }
    }

    // The input-switching features (the paid value). Idempotent via coreStarted.
    private func startCoreFeatures() {
        guard !coreStarted else { return }
        coreStarted = true
        SoundEffect.warm()   // preload the click so the first fix's sound is instant
        hotkeyManager.start()
        autoSwitch.start()          // self-gates on AutoSwitchSettings.isEnabled
        tabMemory.start()
        conversationMemory.start()
        appWatcher.start()
        focusWatcher.start()
    }

    // Gentle, never-blocking reminders, tailored to who the user is:
    //  - grandfathered: the WinRAR-style supporter nag they have always had.
    //  - trial (new user): escalating end-of-trial reminders on the last days.
    //  - licensed / expired: nothing here (expiry is handled by the trial-ended
    //    panel, and licensed users are never prompted). Skipped in UI tests.
    private func runRemindersIfNeeded(for entitlement: Entitlement) {
        switch entitlement {
        case .grandfathered:
            NagController.runIfNeeded()
        case .trial(let daysLeft):
            TrialReminderController.runIfNeeded(daysLeft: daysLeft)
        case .licensed, .expired:
            break
        }
    }

    // Phase 1: prompt for Accessibility access. Real hotkey/AX usage comes later.
    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = """
            FlicKey needs Accessibility access to read window titles \
            and send keystrokes.

            Open System Settings › Privacy & Security › Accessibility and enable \
            FlicKey.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
