import Foundation

// Pure decision for the gentle end-of-trial reminders shown to NEW users during
// their 30-day trial. Grandfathered users never see these (they keep the old
// supporter nag); licensed and expired users never see them either. The reminders
// escalate in clarity as the trial runs down and never block any feature.
//
// No Keychain, no UI, so the decision is deterministically unit-testable. The
// caller persists `newLevel` back into TrialState.trialReminderLevel and shows the
// copy from `message(daysLeft:)`.
enum TrialReminder {
    // Days-left thresholds at which we remind, most relaxed first. For a 30-day
    // trial these land on roughly day 23, 27 and 29. Each threshold fires at most
    // once, so a user sees at most three reminders across the whole trial.
    static let thresholds = [7, 3, 1]

    struct Decision: Equatable {
        var show: Bool
        var newLevel: Int   // persist into TrialState.trialReminderLevel
        var daysLeft: Int
    }

    // `lastLevel` is the smallest threshold already reminded (0 = none yet).
    // We fire when the trial has reached a more urgent (smaller) threshold than
    // the last one we showed. Because daysLeft only shrinks over a trial, this
    // yields exactly one reminder per threshold, in order, and never repeats.
    static func decide(daysLeft: Int, lastLevel: Int) -> Decision {
        let reached = thresholds.filter { daysLeft <= $0 }.min()
        guard let level = reached, lastLevel == 0 || level < lastLevel else {
            return Decision(show: false, newLevel: lastLevel, daysLeft: daysLeft)
        }
        return Decision(show: true, newLevel: level, daysLeft: daysLeft)
    }

    // The escalating reminder copy. Deliberately warm, one time purchase framing,
    // no subscription language, and no em dashes.
    static func message(daysLeft: Int) -> (title: String, body: String) {
        let dayWord = daysLeft == 1 ? "day" : "days"
        let title = "\(daysLeft) \(dayWord) left in your FlicKey trial"
        let body: String
        switch daysLeft {
        case ...1:
            body = "Your free trial ends tomorrow. Unlock FlicKey with a one time "
                + "purchase to keep automatic layout switching and one tap conversion. "
                + "No subscription, and existing features never get taken away."
        case 2...3:
            body = "Your free trial is almost over. If FlicKey has earned a place in "
                + "your day, a one time purchase keeps every feature switched on. "
                + "No subscription."
        default:
            body = "You have about a week left in your free FlicKey trial. Whenever "
                + "you are ready, a one time purchase unlocks it for good. No subscription."
        }
        return (title, body)
    }
}
