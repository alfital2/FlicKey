import Foundation

// The pure decision behind the layout-switch cue (trackpad haptic + optional
// click). Keyed on the active input SOURCE ID, so it generalizes to any number
// of layouts. Change notifications are recorded with noteChange(); once they go
// quiet the controller calls settle(), which announces the FINAL layout's
// configured tap count (1–3) — only if the layout differs from the last
// announced one. Silent when: the layout is unchanged, has no configured count
// (Off), is unknown, or the change fell inside the conversion-suppression
// window. Rapid flip-flops (the OS's own settling bursts, FlicKey's switch
// cascade) therefore produce ONE cue for where the user landed.
struct LayoutCueCore {

    private var lastAnnounced: String?   // sourceID
    private var latest: String?
    private var suppressedUntil: TimeInterval = 0

    init(initialSourceID: String?) {
        lastAnnounced = initialSourceID
        latest = initialSourceID
    }

    // Opens a window during which changes are adopted silently.
    mutating func suppress(for interval: TimeInterval, now: TimeInterval) {
        suppressedUntil = now + interval
    }

    // Record a source-change notification (no decision yet).
    mutating func noteChange(to sourceID: String?) {
        latest = sourceID
    }

    // The burst went quiet: announce the tap count for the layout we landed on,
    // or stay silent. `tapCount` maps a sourceID to 1–3, or nil for "no cue".
    mutating func settle(tapCount: (String) -> Int?, now: TimeInterval) -> Int? {
        let changed = latest != lastAnnounced
        lastAnnounced = latest
        guard changed, let id = latest, now >= suppressedUntil else { return nil }
        return tapCount(id)
    }
}

// Defaults-backed settings for the layout-switch cue. Haptic defaults ON,
// sound is opt-in. Each layout (by input-source ID) gets a tap count 0–3
// (0 = Off); the click sound mirrors the tap count. Perceptual ceiling is 3 —
// more taps aren't reliably distinguishable.
enum LayoutCueSettings {

    static let maxTaps = 3
    // Three haptic strengths, mapped to the OS's actuation IDs (light → strong).
    // The strongest is ID 6 — the tap FlicKey has always used, so it's the default.
    static let hapticLevels = 3
    private static let hapticActuationIDs: [Int32] = [1, 3, 6]

    private static let hapticKey = "layoutCue.haptic.enabled"
    private static let hapticLevelKey = "layoutCue.haptic.level"
    private static let soundKey = "layoutCue.sound.enabled"
    private static let tapsKey = "layoutCue.tapsBySource"

    static var hapticEnabled: Bool {
        get { AppDefaults.store.object(forKey: hapticKey) as? Bool ?? true }
        set { AppDefaults.store.set(newValue, forKey: hapticKey) }
    }

    static var hapticIntensityLevel: Int {
        get {
            guard AppDefaults.store.object(forKey: hapticLevelKey) != nil else { return hapticLevels - 1 }
            return clampLevel(AppDefaults.store.integer(forKey: hapticLevelKey))
        }
        set { AppDefaults.store.set(clampLevel(newValue), forKey: hapticLevelKey) }
    }

    // The private-actuator waveform ID for a strength level.
    static func actuationID(forLevel level: Int) -> Int32 {
        hapticActuationIDs[clampLevel(level)]
    }

    private static func clampLevel(_ n: Int) -> Int { max(0, min(hapticLevels - 1, n)) }

    static var soundEnabled: Bool {
        get { AppDefaults.store.object(forKey: soundKey) as? Bool ?? false }
        set { AppDefaults.store.set(newValue, forKey: soundKey) }
    }

    // Tap count for a layout. A stored value wins; otherwise fall back to a
    // sensible default from the layout's language (English → 1, Hebrew → 2,
    // everything else → 0/Off) so existing English/Hebrew users are unaffected
    // without ever opening Settings.
    static func tapCount(forSourceID id: String, defaultLanguageCode code: String?) -> Int {
        if let stored = stored()[id] { return clamp(stored) }
        switch code?.lowercased() {
        case "en": return 1
        case "he": return 2
        default:   return 0
        }
    }

    static func setTapCount(_ n: Int, forSourceID id: String) {
        var map = stored()
        map[id] = clamp(n)
        AppDefaults.store.set(map, forKey: tapsKey)
    }

    private static func stored() -> [String: Int] {
        AppDefaults.store.dictionary(forKey: tapsKey) as? [String: Int] ?? [:]
    }

    private static func clamp(_ n: Int) -> Int { max(0, min(maxTaps, n)) }
}
