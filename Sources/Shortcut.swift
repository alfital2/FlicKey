import AppKit
import Carbon

// A user-configurable keyboard shortcut for the wrong-layout text fix.
struct Shortcut: Equatable {
    var keyCode: Int64
    var cgFlagsRaw: UInt64 // required modifier mask, as CGEventFlags raw value
    var label: String      // display form, e.g. "⌥2"

    var cgFlags: CGEventFlags { CGEventFlags(rawValue: cgFlagsRaw) }

    // The Hammerspoon original: Option+2.
    static let `default` = Shortcut(keyCode: 19,
                                    cgFlagsRaw: CGEventFlags.maskAlternate.rawValue,
                                    label: "⌥2")
}

// How the conversion is triggered: double-tapping Shift (the default) or a
// chord like ⌥2. Chords ride the Carbon hot key; double-Shift needs its own
// flagsChanged detector (RegisterEventHotKey can't see a bare modifier tap).
enum TriggerKind: String {
    case doubleShift
    case chord
}

// Persists the conversion trigger and notifies listeners when it changes.
enum ShortcutStore {
    private static let keyCodeKey = "conversionShortcut.keyCode"
    private static let flagsKey = "conversionShortcut.flags"
    private static let labelKey = "conversionShortcut.label"
    private static let kindKey = "conversionTrigger.kind"

    // The chord (⌥2 or a recorded one). Used only when the kind is `.chord`.
    static func current() -> Shortcut {
        let defaults = AppDefaults.store
        guard defaults.object(forKey: keyCodeKey) != nil else { return .default }
        return Shortcut(keyCode: Int64(defaults.integer(forKey: keyCodeKey)),
                        cgFlagsRaw: UInt64(defaults.integer(forKey: flagsKey)),
                        label: defaults.string(forKey: labelKey) ?? "?")
    }

    static func set(_ shortcut: Shortcut) {
        let defaults = AppDefaults.store
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
        defaults.set(Int(shortcut.cgFlagsRaw), forKey: flagsKey)
        defaults.set(shortcut.label, forKey: labelKey)
        NotificationCenter.default.post(name: .conversionShortcutChanged, object: nil)
    }

    static func currentKind() -> TriggerKind {
        let defaults = AppDefaults.store
        if let raw = defaults.string(forKey: kindKey), let kind = TriggerKind(rawValue: raw) {
            return kind
        }
        // Migration: if a chord was explicitly stored before this key existed,
        // keep honoring it. Otherwise default to double-Shift.
        return defaults.object(forKey: keyCodeKey) != nil ? .chord : .doubleShift
    }

    static func setKind(_ kind: TriggerKind) {
        AppDefaults.store.set(kind.rawValue, forKey: kindKey)
        NotificationCenter.default.post(name: .conversionShortcutChanged, object: nil)
    }

    // Display label for whatever trigger is currently active.
    static func currentLabel() -> String {
        switch currentKind() {
        case .doubleShift: return "⇧⇧"
        case .chord: return current().label
        }
    }
}

extension Notification.Name {
    static let conversionShortcutChanged = Notification.Name("conversionShortcutChanged")
}

extension Shortcut {
    // Build a Shortcut from a key-down event. Returns nil if no modifier is held
    // (a bare key would clash with normal typing). Used by the recorder UI.
    static func from(_ event: NSEvent) -> Shortcut? {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else { return nil }

        var flags = CGEventFlags()
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.shift) { flags.insert(.maskShift) }

        var label = ""
        if mods.contains(.control) { label += "⌃" }
        if mods.contains(.option) { label += "⌥" }
        if mods.contains(.shift) { label += "⇧" }
        if mods.contains(.command) { label += "⌘" }
        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        label += key.isEmpty ? "key\(event.keyCode)" : key

        return Shortcut(keyCode: Int64(event.keyCode), cgFlagsRaw: flags.rawValue, label: label)
    }
}
