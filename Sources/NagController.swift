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

    private static let panel = GentlePanel()

    // Non-blocking by hard requirement: the modal NSAlert version starved the
    // conversion pipeline while it sat (possibly invisibly) unanswered - QA
    // proved the class on 0.5.0 and caught this exact instance on 0.5.1.
    private static func showNag() {
        panel.show(
            title: "Enjoying FlicKey?",
            body: "FlicKey stays fully functional for you, forever - nothing locks. "
                + "If it saves you time, please consider supporting the project. "
                + "It keeps the updates coming.",
            primary: "Support FlicKey", secondary: "Maybe later",
            onPrimary: { NSWorkspace.shared.open(LicenseStore.buyURL) })
    }
}
