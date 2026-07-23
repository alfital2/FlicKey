import Foundation

// Persistent per-site input memory: { domain -> input source ID }.
// Stores the concrete macOS input source ID (e.g. "com.apple.keylayout.Hebrew-PC"),
// so it generalizes to any enabled layout. No TTL — remembered until changed.
enum SiteMemoryStore {
    private static let key = "siteInputMemory"

    static func sourceID(for domain: String) -> String? {
        let raw = AppDefaults.store.dictionary(forKey: key) as? [String: String] ?? [:]
        return raw[domain]
    }

    static func set(_ sourceID: String, for domain: String) {
        var raw = AppDefaults.store.dictionary(forKey: key) as? [String: String] ?? [:]
        raw[domain] = sourceID
        AppDefaults.store.set(raw, forKey: key)
    }

    static func clear(_ domain: String) {
        var raw = AppDefaults.store.dictionary(forKey: key) as? [String: String] ?? [:]
        raw[domain] = nil
        AppDefaults.store.set(raw, forKey: key)
    }
}
