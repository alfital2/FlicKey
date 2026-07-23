import AppKit

// The gentle, WinRAR-style reminder. The app never locks; once the 7-day trial
// has elapsed and the user isn't licensed, we show a friendly nag at launch,
// then at most every few days (see TrialLogic.nagInterval).
enum NagController {
    // Call once at launch. Honors dev/test launch arguments.
    static func runIfNeeded() {
        let args = ProcessInfo.processInfo.arguments

        // Never nag during UI tests (they also use an isolated defaults store).
        if UITestMode.isActive { return }

        // Dev helpers for exercising the flow without waiting 7 real days.
        // DEBUG-only: must never ship in Release (a public repo would otherwise
        // document a working trial-reset switch for the shipped binary).
        #if DEBUG
        if args.contains("-resetTrial") { TrialManager.reset() }
        if args.contains("-simulateTrialExpired") {
            var state = TrialManager.load()
            state.maxElapsed = TrialLogic.trialLength + 1
            state.lastNag = 0
            TrialManager.save(state)
        }
        #endif

        let decision = TrialManager.recordLaunchAndDecide(isLicensed: LicenseStore.isLicensed)
        guard decision.shouldNag else { return }
        DispatchQueue.main.async { showNag() }   // let launch finish first
    }

    private static func showNag() {
        let alert = NSAlert()
        alert.messageText = "Your 7-day FlicKey trial has ended"
        alert.informativeText = "Good news: nothing locks - FlicKey stays fully functional, forever. "
            + "If it saves you time, please consider supporting the project. It keeps the updates coming."
        alert.addButton(withTitle: "Support FlicKey")
        alert.addButton(withTitle: "Maybe later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(LicenseStore.buyURL)
        }
    }
}
