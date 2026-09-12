import Foundation

// Persistent app-wide memory used by ordinary apps in "Remember last used"
// mode. The management rule remains `.auto`; the changing input source lives in
// a separate store so a remembered value can never turn into a fixed rule.
enum AppLastUsedInputStore {
    private static let key = "appLastUsedInputSources"

    static func sourceID(for identity: String) -> String? {
        values()[identity.lowercased()]
    }

    static func set(_ sourceID: String, for identity: String) {
        guard !identity.isEmpty, !sourceID.isEmpty else { return }
        var current = values()
        current[identity.lowercased()] = sourceID
        AppDefaults.store.set(current, forKey: key)
    }

    static func clear(_ identity: String) {
        var current = values()
        current[identity.lowercased()] = nil
        AppDefaults.store.set(current, forKey: key)
    }

    private static func values() -> [String: String] {
        AppDefaults.store.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
