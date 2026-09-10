import Foundation

// Wires the pure Entitlement decision to the live sources (Keychain trial state +
// license). Kept out of Entitlement.swift so the pure logic stays in the test
// target without pulling in the Keychain.
extension Entitlement {
    static func current(now: Int = Int(Date().timeIntervalSince1970)) -> Entitlement {
        #if DEBUG
        if let override = debugOverride { return override }
        // Debug artifacts are distributed only for QA. They must work on a
        // clean test Mac without a purchase key; otherwise testers cannot reach
        // the features the artifact exists to validate. UI tests deliberately
        // retain the real entitlement path below so trial coverage stays real.
        if !UITestMode.isActive { return .licensed }
        #endif
        return decide(trial: TrialManager.load(), now: now, isLicensed: LicenseStore.isLicensed)
    }

    #if DEBUG
    // Set from launch arguments so the paywall flow can be exercised without a
    // real cutoff or a 30-day wait. Never compiled into release.
    static var debugOverride: Entitlement?

    static func applyDebugOverride(from args: [String]) {
        if args.contains("-simulateExpired") { debugOverride = .expired }
        else if args.contains("-simulateTrialEnding") { debugOverride = .trial(daysLeft: 2) }
        else if args.contains("-simulateTrialFresh") { debugOverride = .trial(daysLeft: 30) }
        else if args.contains("-simulateGrandfathered") { debugOverride = .grandfathered }
        else if args.contains("-simulateLicensed") { debugOverride = .licensed }
    }
    #endif
}
