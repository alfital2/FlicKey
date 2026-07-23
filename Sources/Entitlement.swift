import Foundation

// The pure decision of what a user is entitled to — no Keychain, no UI, so it is
// deterministically unit-testable. It composes the existing TrialState (its
// firstRun stamp and ratcheted maxElapsed) with a grandfather cutoff.
//
// The promise we must keep: everyone who installed while "free forever" was live
// keeps it. That cohort is exactly those whose first-ever launch predates the day
// we publish the paid version — TrialState.firstRun, which is stamped once and
// survives reinstalls. So grandfathering is just `firstRun < cutoff`; no new
// tracking is needed, and it cannot be reset by deleting the app.
enum Entitlement: Equatable {
    case licensed              // a Supporter/License key is active
    case grandfathered         // installed under the free-forever promise — free, forever
    case trial(daysLeft: Int)  // installed after the cutoff, still inside the 30-day trial
    case expired               // installed after the cutoff, trial elapsed — core features gated

    // Everything but a lapsed trial keeps the input-switching features working.
    var coreEnabled: Bool { self != .expired }

    // The free trial length for users who install after the cutoff.
    static let trialLength = 30 * 24 * 60 * 60
    private static let day = 24 * 60 * 60

    // The release date of the paid version, as epoch seconds. Anyone whose first
    // launch predates this installed under the free-forever promise and is
    // grandfathered — matching the published Terms' grandfather clause.
    static let grandfatherCutoff = 1_784_764_800   // 2026-07-23 00:00 UTC (Terms effective date)

    static func decide(trial: TrialState, now: Int, isLicensed: Bool,
                       cutoff: Int = grandfatherCutoff) -> Entitlement {
        if isLicensed { return .licensed }
        // Installed while the promise was live (strictly before the cutoff).
        if trial.firstRun < cutoff { return .grandfathered }
        // A genuinely new user: apply the trial, honoring the clock-rollback
        // ratchet so setting the system clock back can't revive a lapsed trial.
        let elapsed = max(trial.maxElapsed, max(0, now - trial.firstRun))
        guard elapsed < trialLength else { return .expired }
        let daysLeft = (trialLength - elapsed + day - 1) / day   // round up
        return .trial(daysLeft: daysLeft)
    }
}
