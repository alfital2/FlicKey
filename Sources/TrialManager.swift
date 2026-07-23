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
           let state = try? JSONDecoder().decode(TrialState.self, from: data) {
            return state
        }
        let fresh = TrialLogic.start(now: now())   // first ever launch
        save(fresh)
        return fresh
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
