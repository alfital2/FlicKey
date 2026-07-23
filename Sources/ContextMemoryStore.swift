import Foundation

// Persistent per-conversation input memory, namespaced per provider:
//   { namespace -> { conversationKey -> input source ID } }
//
// Same model as SiteMemoryStore (which remains the browser per-site store),
// generalized so each ConversationProvider gets its own keyspace. Stores the
// concrete macOS input source ID, so it generalizes to any enabled layout.
// No TTL — remembered until changed.
enum ContextMemoryStore {
    private static let defaultsKey = "conversationInputMemory"

    static func sourceID(namespace: String, key: String) -> String? {
        table()[namespace]?[key]
    }

    static func set(_ sourceID: String, namespace: String, key: String) {
        var all = table()
        var ns = all[namespace] ?? [:]
        ns[key] = sourceID
        all[namespace] = ns
        save(all)
    }

    // MARK: - Backing store

    private static func table() -> [String: [String: String]] {
        (AppDefaults.store.dictionary(forKey: defaultsKey) as? [String: [String: String]]) ?? [:]
    }

    private static func save(_ table: [String: [String: String]]) {
        AppDefaults.store.set(table, forKey: defaultsKey)
    }
}
