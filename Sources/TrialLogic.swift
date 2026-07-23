import Foundation

// Pure trial/nag decision logic — no Keychain, no UI — so it's unit-testable.
// `maxElapsed` is a ratchet: elapsed time since first run can only ever grow, so
// rolling the system clock back can't lengthen the trial, and there's no fragile
// "tampering detected" state to get wrong (timezones / NTP corrections are safe).
struct TrialState: Codable, Equatable {
    var firstRun: Int    // epoch seconds
    var maxElapsed: Int  // ratcheted seconds observed since firstRun
    var lastNag: Int     // epoch seconds, 0 = never nagged
    // Smallest days-left threshold at which we have already shown a new-user
    // trial reminder (see TrialReminder). Optional so old Keychain records that
    // predate this field still decode cleanly (absent key becomes nil, i.e. none
    // shown yet) instead of failing and resetting the ratchet.
    var trialReminderLevel: Int? = nil
}

struct TrialDecision: Equatable {
    var trialActive: Bool
    var daysUsed: Int
    var shouldNag: Bool
    var newState: TrialState
}

enum TrialLogic {
    static let trialLength = 7 * 24 * 60 * 60   // 7 days
    static let nagInterval = 3 * 24 * 60 * 60   // remind every 3 days after expiry
    private static let day = 24 * 60 * 60

    static func start(now: Int) -> TrialState {
        TrialState(firstRun: now, maxElapsed: 0, lastNag: 0)
    }

    static func decide(state: TrialState, now: Int, isLicensed: Bool) -> TrialDecision {
        let elapsed = max(state.maxElapsed, max(0, now - state.firstRun))  // ratchet
        var newState = state
        newState.maxElapsed = elapsed

        let trialActive = elapsed < trialLength
        var shouldNag = false
        if !isLicensed && !trialActive {
            // Nag on the first expired launch, then every nagInterval.
            shouldNag = state.lastNag == 0 || (now - state.lastNag >= nagInterval)
        }
        if shouldNag { newState.lastNag = now }

        return TrialDecision(trialActive: trialActive,
                             daysUsed: elapsed / day,
                             shouldNag: shouldNag,
                             newState: newState)
    }
}
