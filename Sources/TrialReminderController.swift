import AppKit

// Shows the gentle end-of-trial reminders to a NEW user during their 30-day
// trial, at most once per threshold (see TrialReminder). This is the trial
// counterpart of NagController (which serves grandfathered users). The app keeps
// working the whole time; this only surfaces a friendly, escalating prompt.
enum TrialReminderController {
    // Called from the entitlement refresh whenever the user is in trial. Decides
    // (purely) whether this launch has crossed a not-yet-shown reminder threshold,
    // persists that we showed it, then presents the prompt.
    static func runIfNeeded(daysLeft: Int) {
        if UITestMode.isActive { return }

        let state = TrialManager.load()
        let decision = TrialReminder.decide(daysLeft: daysLeft,
                                            lastLevel: state.trialReminderLevel ?? 0)
        guard decision.show else { return }

        var updated = state
        updated.trialReminderLevel = decision.newLevel
        TrialManager.save(updated)

        // Defer past launch: a menu-bar (LSUIElement) app cannot bring a window
        // forward while still inside applicationDidFinishLaunching.
        DispatchQueue.main.async { show(daysLeft: decision.daysLeft) }
    }

    private static let panel = GentlePanel()

    // Non-blocking by hard requirement (same class as the nag): a modal alert at
    // launch starves the conversion pipeline until dismissed.
    private static func show(daysLeft: Int) {
        let copy = TrialReminder.message(daysLeft: daysLeft)
        panel.show(
            title: copy.title,
            body: copy.body,
            primary: "Unlock FlicKey", secondary: "Keep trying it",
            onPrimary: { NSWorkspace.shared.open(LicenseStore.buyURL) })
    }
}
