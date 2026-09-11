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

enum AutoSwitchMonitorIssue: Equatable {
    case accessibilityDenied
    case monitorCreationFailed
}

enum AutoSwitchMonitorHealthState: Equatable {
    case inactive
    case available
    case unavailable(AutoSwitchMonitorIssue)
}

// Process-local state used to explain when Auto-fix is enabled but cannot see
// global keystrokes. It contains no typing data.
enum AutoSwitchMonitorHealth {
    private(set) static var state: AutoSwitchMonitorHealthState = .inactive

    static func set(_ newState: AutoSwitchMonitorHealthState) {
        guard state != newState else { return }
        state = newState
        NotificationCenter.default.post(name: .autoSwitchMonitorHealthChanged, object: nil)
    }
}

extension Notification.Name {
    // Posted when the auto-switch toggle changes, so the controller starts/stops live.
    static let autoSwitchSettingChanged = Notification.Name("flickey.autoSwitchSettingChanged")
    static let autoSwitchMonitorHealthChanged = Notification.Name("flickey.autoSwitchMonitorHealthChanged")
}
