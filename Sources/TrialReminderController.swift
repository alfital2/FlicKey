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

    private static func show(daysLeft: Int) {
        let copy = TrialReminder.message(daysLeft: daysLeft)
        let alert = NSAlert()
        alert.messageText = copy.title
        alert.informativeText = copy.body
        alert.addButton(withTitle: "Unlock FlicKey")
        alert.addButton(withTitle: "Keep trying it")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(LicenseStore.buyURL)
        }
    }
}
