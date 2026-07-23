import Foundation

// The one-time welcome tour for NEW users: a small animated walkthrough of what
// FlicKey does, shown on the first launch after a fresh install. Existing users
// never see it (they get the What's New note instead); the Support tab has a
// button to replay it anytime.
enum WelcomeTour {
    // A fresh install is "firstRun stamped moments ago". The Keychain-persisted
    // TrialState.firstRun is written once on the first-ever launch, so an install
    // whose firstRun is older than this window belongs to an existing user.
    static let freshInstallWindow: TimeInterval = 6 * 60 * 60

    // Pure gate so it is unit-testable: show only for an unseen, genuinely fresh
    // install.
    static func shouldShow(firstRun: TimeInterval, now: TimeInterval, seen: Bool) -> Bool {
        guard !seen else { return false }
        return now - firstRun < freshInstallWindow
    }
}

enum WelcomeTourStore {
    private static let key = "welcomeTourSeen"
    static var seen: Bool {
        get { AppDefaults.store.bool(forKey: key) }
        set { AppDefaults.store.set(newValue, forKey: key) }
    }
}
