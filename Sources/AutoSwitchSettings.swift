import Foundation

// Opt-in switch for auto-correct. Default OFF: the feature mutates text
// automatically, so it ships disabled and the user turns it on in General settings.
enum AutoSwitchSettings {
    private static let key = "autoSwitchEnabled"

    static var isEnabled: Bool {
        get { AppDefaults.store.bool(forKey: key) }   // absent → false
        set {
            AppDefaults.store.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .autoSwitchSettingChanged, object: nil)
        }
    }
}

enum AutoSwitchMonitorIssue: String, Codable, Equatable {
    case accessibilityDenied
    case monitorCreationFailed
}

enum AutoSwitchMonitorHealthState: Equatable {
    case inactive
    case available
    case unavailable(AutoSwitchMonitorIssue)
}

// Process-local health exposed to Settings. This contains no typing data; it is
// only whether the global keyboard monitor exists and, if not, the categorical
// reason. AutoSwitchController owns updates on the main thread.
enum AutoSwitchMonitorHealth {
    private(set) static var state: AutoSwitchMonitorHealthState = .inactive

    static func set(_ newState: AutoSwitchMonitorHealthState) {
        guard state != newState else { return }
        state = newState
        NotificationCenter.default.post(name: .autoSwitchMonitorHealthChanged, object: nil)
    }
}

// Retry quickly while the user is granting permission, then stop as soon as the
// monitor is live. There is no steady-state polling cost.
struct AutoSwitchMonitorRecoverySchedule {
    static let delays: [TimeInterval] = [0.25, 0.5, 1, 2, 5, 10]
    private(set) var attemptsIssued = 0

    mutating func takeNextDelay() -> TimeInterval {
        let delay = Self.delays[min(attemptsIssued, Self.delays.count - 1)]
        attemptsIssued += 1
        return delay
    }

    mutating func reset() { attemptsIssued = 0 }
}

extension Notification.Name {
    // Posted when the auto-switch toggle changes, so the controller starts/stops live.
    static let autoSwitchSettingChanged = Notification.Name("flickey.autoSwitchSettingChanged")
    static let autoSwitchMonitorHealthChanged = Notification.Name("flickey.autoSwitchMonitorHealthChanged")
}
