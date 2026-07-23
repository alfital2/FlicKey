import AppKit

// Reads macOS's "Automatically switch to a document's input source" setting
// (System Settings ▸ Keyboard). When ON, macOS changes the keyboard layout
// per document/tab, which fights FlicKey's per-site memory, so we surface a
// warning when it's enabled.
enum OSAutoSwitch {
    private static let appID = "com.apple.HIToolbox" as CFString
    private static let propsKey = "AppleGlobalTextInputProperties" as CFString
    private static let flagKey = "TextInputGlobalPropertyPerContextInput"
    private static let keyboardSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    static func isEnabled() -> Bool {
        CFPreferencesAppSynchronize(appID)
        guard let props = CFPreferencesCopyAppValue(propsKey, appID) as? [String: Any],
              let value = props[flagKey] as? Int
        else { return false }
        return value == 1
    }

    // Opens System Settings straight to the Keyboard pane, where the offending
    // toggle and the input-source list live.
    static func openKeyboardSettings() {
        NSWorkspace.shared.open(keyboardSettingsURL)
    }
}
