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

    private static func now() -> Int { Int(Date().timeIntervalSince1970) }

    static func load() -> TrialState {
        if let data = Keychain.get(service: service, account: account),
           let state = try? JSONDecoder().decode(TrialState.self, from: data),
           state.firstRun > 0 {   // reject crafted/corrupt records (firstRun 0 = "forever")
            return state
        }
        // No readable record. Distinguish a genuinely fresh install from an
        // EXISTING install whose Keychain record was lost (migration, keychain
        // reset, restore): re-stamping an old user as "first run today" would
        // silently turn a grandfathered free-forever user into a 30-day trial -
        // a broken promise (QA 0.5.1-diag finding). Evidence of prior use in our
        // defaults domain means this Mac ran FlicKey before; stamp it as
        // pre-cutoff so the grandfather clause holds. The failure direction is
        // deliberate: when in doubt, the user gets FlicKey free.
        let fresh: TrialState
        if hasEvidenceOfPriorUse() {
            fresh = TrialState(firstRun: Entitlement.grandfatherCutoff - 1, maxElapsed: 0, lastNag: 0)
        } else {
            fresh = TrialLogic.start(now: now())   // first ever launch
        }
        save(fresh)
        return fresh
    }

    // Long-lived keys that only exist after real prior use of FlicKey (never
    // written during the launch path that runs before the first load()).
    private static func hasEvidenceOfPriorUse() -> Bool {
        let markers = ["hasCompletedFirstLaunch", "whatsNewSeenVersion", "welcomeTourSeen",
                       "autoSwitchExceptions", "clickSound.variant", "switchStats.autoFix",
                       "statsNagLastMilestone", "blockedWordsLastPromptAt"]
        return markers.contains { AppDefaults.store.object(forKey: $0) != nil }
    }

    // Marks that this install has completed a launch - the primary prior-use
    // marker for the keychain-loss heuristic above. Called at the END of the
    // launch path, after the first load() has already run.
    static func markLaunchCompleted() {
        AppDefaults.store.set(true, forKey: "hasCompletedFirstLaunch")
    }

    // Persist the clock-rollback ratchet for EVERY user at launch. Previously
    // only the grandfathered nag path saved the ratcheted state, so a trial user
    // could roll the clock back and freeze the trial (QA 0.5.1-diag finding).
    static func persistRatchet() {
        let decision = TrialLogic.decide(state: load(), now: now(), isLicensed: true)  // true = never nags
        save(decision.newState)
    }

    static func save(_ state: TrialState) {
        if let data = try? JSONEncoder().encode(state) {
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
    }
}
