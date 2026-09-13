import Foundation

// Detects a surviving preferences domain from an older FlicKey installation.
// This is intentionally pure so migration behavior can be tested without ever
// reading or changing a customer's Keychain.
enum PriorUseEvidence {
    static let markerKeys = [
        "hasCompletedFirstLaunch", "whatsNewSeenVersion", "welcomeTourSeen",
        "conversionShortcut.keyCode", "conversionShortcut.flags", "conversionShortcut.label",
        "conversionTrigger.kind", "appInputOverrides", "customApps", "hiddenBuiltins",
        "importAllApps", "rememberVisitedApps", "siteInputMemory", "conversationInputMemory",
        "autoSwitchEnabled", "autoSwitchExceptions", "clickSound.enabled", "clickSound.variant",
        "clickSound.volumeLevel", "layoutCue.haptic.enabled", "layoutCue.haptic.level",
        "layoutCue.sound.enabled", "layoutCue.tapsBySource", "menuBarIconStyle",
        "switchStats.autoFix", "statsNagDisabled", "statsNagLastMilestone",
        "blockedWordsLastPromptAt", "blockedWordsAlreadyOffered"
    ]

    static func exists(in store: UserDefaults) -> Bool {
        markerKeys.contains { store.object(forKey: $0) != nil }
    }
}
