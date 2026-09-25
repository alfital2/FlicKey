import Foundation

// Decide which trial stamp survives a missing or temporarily unreadable
// Keychain record. The defaults backup is written on every successful launch;
// ordinary preferences alone only prove prior use for older app versions.
enum TrialRecovery {
    static func choose(keychain: TrialState?, backup: TrialState?,
                       backupWasPresent: Bool, priorUse: Bool, now: Int) -> TrialState {
        if let keychain, let backup {
            var state = keychain
            state.firstRun = min(keychain.firstRun, backup.firstRun)
            state.maxElapsed = max(keychain.maxElapsed, backup.maxElapsed)
            state.lastNag = max(keychain.lastNag, backup.lastNag)
            return state
        }
        if let keychain { return keychain }
        if let backup { return backup }
        // A damaged backup is evidence of a paid-era install. Do not let its
        // remaining ordinary settings turn it into a grandfathered user.
        if backupWasPresent {
            return TrialState(firstRun: Entitlement.grandfatherCutoff,
                              maxElapsed: Entitlement.trialLength, lastNag: 0)
        }
        if priorUse {
            return TrialState(firstRun: Entitlement.grandfatherCutoff - 1,
                              maxElapsed: 0, lastNag: 0)
        }
        return TrialLogic.start(now: now)
    }
}
