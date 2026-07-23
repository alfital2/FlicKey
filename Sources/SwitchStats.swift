import Foundation

extension Notification.Name {
    static let switchStatsChanged = Notification.Name("com.talalfi.FlicKey.switchStatsChanged")
}

// The kinds of input-source change FlicKey makes for the user. Every one is
// counted so the stats tab can show a fun, running tally.
enum SwitchKind: String, CaseIterable {
    case autoFix
    case manualConvert
    case appSwitch
    case siteSwitch
    case chatSwitch

    var label: String {
        switch self {
        case .autoFix:       return "Auto-fixed wrong-layout typing"
        case .manualConvert: return "Converted on demand (double-tap Shift)"
        case .appSwitch:     return "Switched by app"
        case .siteSwitch:    return "Switched by website"
        case .chatSwitch:    return "Switched by chat"
        }
    }

    var symbol: String {
        switch self {
        case .autoFix:       return "wand.and.stars"
        case .manualConvert: return "shift"
        case .appSwitch:     return "macwindow"
        case .siteSwitch:    return "globe"
        case .chatSwitch:    return "bubble.left.and.bubble.right"
        }
    }
}

// A running, persisted tally of every layout change FlicKey performs. Purely
// additive per-kind counters in UserDefaults; the total is their sum, so it can
// never drift. Recording posts a notification so the stats tab title and the
// milestone nudge can react.
enum SwitchStats {
    private static var store: UserDefaults { AppDefaults.store }
    private static func key(_ kind: SwitchKind) -> String { "switchStats.\(kind.rawValue)" }

    static func record(_ kind: SwitchKind) {
        store.set(count(kind) + 1, forKey: key(kind))
        NotificationCenter.default.post(name: .switchStatsChanged, object: nil)
    }

    static func count(_ kind: SwitchKind) -> Int { store.integer(forKey: key(kind)) }
    static var total: Int { SwitchKind.allCases.reduce(0) { $0 + count($1) } }
    static var breakdown: [(kind: SwitchKind, count: Int)] {
        SwitchKind.allCases.map { (kind: $0, count: count($0)) }
    }
}
