import Foundation

// Keychain-backed adapter around the pure TrialLogic. Trial state lives in the
// Keychain so it survives app delete/reinstall (a fresh prefs file won't reset
// the trial). All decisions come from TrialLogic; this just loads/saves.
enum TrialManager {
    // UI tests get their own Keychain item so they can never read or ratchet
    // the user's real trial state (mirrors AppDefaults.useIsolatedStoreForUITests).
    private static var service: String {
        UITestMode.isActive ? "com.talalfi.FlicKey.trial.uitest"
                            : "com.talalfi.FlicKey.trial"
    }
    private static let account = "trial"
    private static let backupKey = "trialStateBackup.v1"

    private static func now() -> Int { Int(Date().timeIntervalSince1970) }

    static func load() -> TrialState {
        let keychainState = Keychain.get(service: service, account: account)
            .flatMap { try? JSONDecoder().decode(TrialState.self, from: $0) }
            .flatMap { $0.firstRun > 0 ? $0 : nil }
        let backupData = AppDefaults.store.data(forKey: backupKey)
        let backupState = backupData
            .flatMap { try? JSONDecoder().decode(TrialState.self, from: $0) }
            .flatMap { $0.firstRun > 0 ? $0 : nil }
        let state = TrialRecovery.choose(
            keychain: keychainState, backup: backupState,
            backupWasPresent: AppDefaults.store.object(forKey: backupKey) != nil,
            priorUse: PriorUseEvidence.exists(in: AppDefaults.store), now: now())
        // Migrate old records into the backup, and restore either surviving
        // record into the other store. Save also ratchets toward the older stamp.
        if state != keychainState || state != backupState { save(state) }
        return state
    }

    // Marks that this install has completed a launch - the primary prior-use
    // marker for the keychain-loss heuristic above. Called at the END of the
    // launch path, after the first load() has already run.
    static func markLaunchCompleted() {
        // Never create legacy prior-use evidence for a fresh user unless the
        // first-run stamp survived in at least one store.
        if Keychain.get(service: service, account: account) != nil ||
            AppDefaults.store.data(forKey: backupKey) != nil {
            AppDefaults.store.set(true, forKey: "hasCompletedFirstLaunch")
        }
    }

    // Persist the clock-rollback ratchet for EVERY user at launch. Previously
    // only the grandfathered nag path saved the ratcheted state, so a trial user
    // could roll the clock back and freeze the trial (QA 0.5.1-diag finding).
    static func persistRatchet(minimumAdvance: Int = 0) {
        let state = load()
        let decision = TrialLogic.decide(state: state, now: now(), isLicensed: true)  // true = never nags
        if decision.newState.maxElapsed - state.maxElapsed >= minimumAdvance ||
            (state.maxElapsed < Entitlement.trialLength &&
             decision.newState.maxElapsed >= Entitlement.trialLength) {
            save(decision.newState)
        }
    }

    static func save(_ state: TrialState) {
        if let data = try? JSONEncoder().encode(state) {
            AppDefaults.store.set(data, forKey: backupKey)
            Keychain.set(data, service: service, account: account)
        }
    }

    // Called once at launch: ratchets elapsed and decides whether to nag,
    // persisting the result (including a new lastNag if we nag).
    static func recordLaunchAndDecide(isLicensed: Bool) -> TrialDecision {
        let decision = TrialLogic.decide(state: load(), now: now(), isLicensed: isLicensed)
        save(decision.newState)
        return decision
    }

    // Read-only status for the Settings view (never counts as a nag).
    static func status() -> (daysUsed: Int, trialActive: Bool) {
        let decision = TrialLogic.decide(state: load(), now: now(), isLicensed: true)
        save(decision.newState)   // persist the ratchet, but isLicensed:true ⇒ no nag
        return (decision.daysUsed, decision.trialActive)
    }

    static func reset() {
        Keychain.delete(service: service, account: account)
        AppDefaults.store.removeObject(forKey: backupKey)
    }
}
