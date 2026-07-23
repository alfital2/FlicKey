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

extension Notification.Name {
    // Posted when the auto-switch toggle changes, so the controller starts/stops live.
    static let autoSwitchSettingChanged = Notification.Name("flickey.autoSwitchSettingChanged")
}
