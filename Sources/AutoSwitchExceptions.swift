import Foundation

// Tracks which words the user does NOT want auto-switched, learned from behavior
// rather than a one-off gesture. Each word carries a rejection count: undoing an
// auto-fix (⇧⇧) records a rejection, accepting one (letting it stand) resets the
// count to zero. A word is blocked only once it reaches `blockThreshold`
// rejections (default 2), so a single accidental undo never permanently blocks a
// word the user actually wants converted, and a later acceptance forgives it.
//
// The UserDefaults store is the single source of truth, re-read on every call, so
// separate instances (the running controller and the Settings sheet) always agree
// — removing a word in Settings takes effect for detection immediately. Persisted
// (a learned username/brand should survive launches), capped so it can never grow
// without bound, and normalized (trim + lowercase) so case and spacing don't
// fragment entries.
final class AutoSwitchExceptions {
    private let store: UserDefaults
    private let blockThreshold: Int
    private let cap: Int
    private let key = "autoSwitchExceptions"

    init(store: UserDefaults = AppDefaults.store, blockThreshold: Int = 2, cap: Int = 500) {
        self.store = store
        self.blockThreshold = max(1, blockThreshold)
        self.cap = cap
    }

    // Whether this word is currently blocked from auto-switching.
    func isBlocked(_ word: String) -> Bool {
        (load()[Self.normalize(word)] ?? 0) >= blockThreshold
    }

    // The user undid an auto-fix of this word: one more rejection.
    func recordRejection(_ word: String) {
        let n = Self.normalize(word)
        guard !n.isEmpty else { return }
        var counts = load()
        counts[n, default: 0] += 1
        save(evictingToCap(counts, keeping: n))
    }

    // The user accepted an auto-fix of this word (or manually converted it): the
    // conversion is what they wanted, so forget any rejections.
    func recordAcceptance(_ word: String) {
        let n = Self.normalize(word)
        var counts = load()
        guard counts[n] != nil else { return }
        counts[n] = nil
        save(counts)
    }

    // Blocked words (alphabetical for a stable Settings list). Beta reports use
    // only the count.
    func blockedWords() -> [String] {
        load().filter { $0.value >= blockThreshold }.keys.sorted()
    }
    var count: Int { load().values.filter { $0 >= blockThreshold }.count }

    func unblock(_ word: String) {
        var counts = load()
        guard counts[Self.normalize(word)] != nil else { return }
        counts[Self.normalize(word)] = nil
        save(counts)
    }

    func clearAll() { store.removeObject(forKey: key) }

    // MARK: - Backing store

    private func load() -> [String: Int] {
        (store.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    private func save(_ counts: [String: Int]) {
        counts.isEmpty ? store.removeObject(forKey: key) : store.set(counts, forKey: key)
    }

    // Keep the map bounded: when over the cap, drop the lowest-count entries
    // first (the least-committed rejections), so genuinely blocked words survive.
    // The word being recorded right now is exempt — it enters at the minimum
    // count, so lowest-count eviction would otherwise drop it every time and its
    // rejections could never accumulate to the threshold.
    private func evictingToCap(_ counts: [String: Int], keeping exempt: String) -> [String: Int] {
        guard counts.count > cap else { return counts }
        var kept = counts.filter { $0.key != exempt }
            .sorted { $0.value > $1.value }
            .prefix(cap - 1)
            .reduce(into: [String: Int]()) { $0[$1.key] = $1.value }
        kept[exempt] = counts[exempt]
        return kept
    }

    private static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
