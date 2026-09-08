import AppKit

// What input an app should use: a specific macOS input source, or AUTO
// (browsers only — input is learned/applied per website at runtime).
enum InputRule: Equatable {
    case source(String) // input source ID, e.g. "com.apple.keylayout.Hebrew-PC"
    case auto

    var sourceID: String? { if case .source(let id) = self { return id }; return nil }
    var isAuto: Bool { if case .auto = self { return true }; return false }

    var fallbackSymbol: String { isAuto ? "globe" : "keyboard" }

    // Persisted string form.
    static let autoToken = "__auto__"
    var storageValue: String { isAuto ? Self.autoToken : (sourceID ?? "") }
    init?(storage: String) {
        if storage == Self.autoToken { self = .auto }
        else if !storage.isEmpty { self = .source(storage) }
        else { return nil }
    }
}

// How an app's input is managed:
//   .normal       — a forced input source.
//   .browser      — AUTO (per-site) by default; a forced source overrides it.
//   .conversation — AUTO (per-conversation, via a ConversationProvider) by
//                   default; a forced source overrides it.
enum AppKind {
    case normal, browser, conversation
}

struct AppRule {
    let name: String      // display name; matched against the normalized app name
    let bundleID: String  // resolves the app's real icon
    let rule: InputRule   // effective rule (default merged with any user override)
    let isCustom: Bool    // user-added (removable) vs. built-in
    let kind: AppKind

    var isBrowser: Bool { kind == .browser }
    var isConversationApp: Bool { kind == .conversation }
    var matchKey: String { name.lowercased() }
}

// A user-added app, persisted in UserDefaults.
struct CustomApp: Codable {
    let name: String
    let bundleID: String
}

// Single source of truth for per-app input rules, shared by AppWatcher (to act)
// and the preferences window (to display + edit). User edits (language overrides
// and custom apps) are persisted via RulesStore and merged over these defaults.
enum AppRules {

    // langHint ("en"/"he") is resolved to one of the user's enabled input
    // sources at runtime; nil for browsers (they default to AUTO).
    private static let defaults: [(name: String, bundleID: String, langHint: String?)] = [
        ("PyCharm", "com.jetbrains.pycharm", "en"),
        ("WebStorm", "com.jetbrains.WebStorm", "en"),
        ("VSCodium", "com.vscodium", "en"),
        ("Xcode", "com.apple.dt.Xcode", "en"),
        ("LM Studio", "ai.elementlabs.lmstudio", "en"),
        ("Ollama", "com.electron.ollama", "en"),
        ("Keynote", "com.apple.Keynote", "en"),
        ("Numbers", "com.apple.Numbers", "en"),
        ("Final Cut Pro", "com.apple.FinalCut", "en"),
        ("Motion", "com.apple.motionapp", "en"),
        ("Compressor", "com.apple.Compressor", "en"),
        ("Logic Pro", "com.apple.logic10", "en"),
        ("GarageBand", "com.apple.garageband10", "en"),
        ("Terminal", "com.apple.Terminal", "en"),
        ("WhatsApp", "net.whatsapp.WhatsApp", "he"),
        ("Pages", "com.apple.iWork.Pages", "he"),
        ("zoom.us", "us.zoom.xos", "he"),
    ]

    private static var builtinKeys: Set<String> {
        Set(defaults.map { $0.name.lowercased() }
            + BrowserCatalog.installed().map { $0.name.lowercased() })
    }

    // Built-ins + custom apps, with persisted overrides applied. Built-ins the
    // user removed are hidden; uninstalled browsers are skipped.
    static var all: [AppRule] {
        let overrides = RulesStore.overrides()
        let hidden = RulesStore.hiddenBuiltins()
        let sources = InputSourceCatalog.enabledSources() // resolve hints once
        var seen = Set<String>()
        var result: [AppRule] = []
        let browsers = BrowserCatalog.installed()
        let browserBundleIDs = Set(browsers.map { $0.bundleID.lowercased() })

        for entry in defaults {
            let key = entry.name.lowercased()
            seen.insert(key)
            guard !hidden.contains(key) else { continue }
            result.append(AppRule(
                name: entry.name,
                bundleID: entry.bundleID,
                rule: resolveRule(overrides[key], autoByDefault: false,
                                  langHint: entry.langHint, sources: sources),
                isCustom: false,
                kind: .normal
            ))
        }

        // LaunchServices-discovered browsers occupy the same position the old
        // hardcoded browser rows did: before custom apps, defaulting to AUTO.
        // Keeping the display-name match key preserves existing overrides and
        // hidden rows for Safari, Chrome, Firefox, and the other former defaults.
        for browser in browsers {
            let key = browser.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            guard !hidden.contains(key) else { continue }
            result.append(AppRule(
                name: browser.name,
                bundleID: browser.bundleID,
                rule: resolveRule(overrides[key], autoByDefault: true,
                                  langHint: nil, sources: sources),
                isCustom: false,
                kind: .browser
            ))
        }

        for custom in RulesStore.customApps() {
            let key = custom.name.lowercased()
            guard !seen.contains(key) else { continue }
            // Identity for conversation-provider apps (e.g. Teams) is by BUNDLE
            // ID, not name. A stray/legacy custom entry for such an app (any
            // name/variant) must not shadow the provider as a forced .normal row
            // — that would route to .force and silently kill per-conversation
            // memory. Skip it; the provider owns the app below.
            if ConversationProviderRegistry.provider(forBundleID: custom.bundleID) != nil { continue }
            // Likewise, a custom entry added before browser discovery must not
            // force one layout for the whole browser and disable per-site memory.
            if browserBundleIDs.contains(custom.bundleID.lowercased()) { continue }
            seen.insert(key)
            result.append(AppRule(
                name: custom.name,
                bundleID: custom.bundleID,
                rule: resolveRule(overrides[key], autoByDefault: false,
                                  langHint: "en", sources: sources),
                isCustom: true,
                kind: .normal
            ))
        }

        // Conversation-provider apps (e.g. Teams): listed when installed, like
        // browsers, defaulting to AUTO (per-conversation). A forced source
        // overrides per-conversation for the whole app.
        for app in ConversationProviderRegistry.installedApps() {
            let key = app.displayName.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            guard !hidden.contains(key) else { continue }   // honor user removal
            result.append(AppRule(
                name: app.displayName,
                bundleID: app.bundleID,
                rule: resolveRule(overrides[key], autoByDefault: true,
                                  langHint: nil, sources: sources),
                isCustom: false,
                kind: .conversation
            ))
        }
        return result
    }

    // An explicit override wins; otherwise apps that manage input automatically
    // (browsers, conversation apps) default to AUTO, and others to the enabled
    // source matching their language hint (else the first source).
    private static func resolveRule(_ override: String?, autoByDefault: Bool,
                                    langHint: String?, sources: [InputSourceInfo]) -> InputRule {
        if let override, let rule = InputRule(storage: override) { return rule }
        if autoByDefault { return .auto }
        if let hint = langHint,
           let id = (sources.first { $0.languageCodes.first == hint }
                     ?? sources.first { $0.languageCodes.contains(hint) })?.id {
            return .source(id)
        }
        // macOS always has at least one enabled keyboard source, so this guard holds
        // in practice. Falling back to AUTO (rather than an empty-ID .source that
        // InputRule itself rejects and switchTo can't apply) keeps the degenerate
        // empty case a harmless no-op.
        guard let first = sources.first else { return .auto }
        return .source(first.id)
    }

    // All apps the user can configure, sorted alphabetically. Browsers get an
    // AUTO (per-site) option; other apps pick any one enabled input source.
    static var editable: [AppRule] {
        all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Effective rule for an already-normalized (lowercased) app name.
    static func rule(forNormalizedName name: String) -> InputRule? {
        all.first { $0.matchKey == name }?.rule
    }

    // Prefer stable bundle identity for a running app. Name fallback preserves
    // custom/built-in behavior when an old or unusual app has no bundle ID.
    static func rule(for app: NSRunningApplication) -> InputRule? {
        rule(forBundleID: app.bundleIdentifier,
             normalizedName: normalizedName(app.localizedName))
    }

    static func rule(forBundleID bundleID: String?, normalizedName name: String) -> InputRule? {
        let rules = all
        if let bundleID,
           let match = rules.first(where: {
               $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame
           }) {
            return match.rule
        }
        return name.isEmpty ? nil : rules.first { $0.matchKey == name }?.rule
    }

    // App names can carry zero-width / bidi format characters; strip them and
    // lowercase so matching is stable across locales and stray Unicode. Shared
    // by AppWatcher (activation) and FocusWatcher (focus events) so both resolve
    // a running app to the exact same rule.
    static func normalizedName(_ raw: String?) -> String {
        guard let raw = raw else { return "" }
        let visible = raw.unicodeScalars.filter {
            !$0.properties.isDefaultIgnorableCodePoint
        }
        return String(String.UnicodeScalarView(visible))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // The forced input-source ID for a running app, or nil when it has no forced
    // rule (browsers/conversation apps default to AUTO → nil; unlisted → nil).
    // FocusWatcher uses this to decide which apps to observe and what to apply.
    static func forcedSourceID(forAppNamed raw: String?) -> String? {
        let key = normalizedName(raw)
        guard !key.isEmpty else { return nil }
        return rule(forNormalizedName: key)?.sourceID
    }

    static func setRule(_ rule: InputRule, for app: AppRule) {
        RulesStore.set(rule.storageValue, forMatchKey: app.matchKey)
        NotificationCenter.default.post(name: .appRulesChanged, object: nil)
    }

    // Remove an app so it no longer follows any rule: custom apps are deleted,
    // built-ins are hidden (persisted) so they don't reappear.
    static func remove(_ app: AppRule) {
        if app.isCustom {
            RulesStore.removeCustomApp(matchKey: app.matchKey)
        } else {
            RulesStore.hideBuiltin(matchKey: app.matchKey)
        }
        NotificationCenter.default.post(name: .appRulesChanged, object: nil)
    }

    // Add an app. Returns false if it's already listed. Restores a previously
    // removed built-in instead of creating a duplicate custom entry.
    @discardableResult
    static func addCustom(_ custom: CustomApp) -> Bool {
        // Discovered browsers own their bundle IDs and default to per-site AUTO.
        // Re-adding a hidden browser restores its canonical discovered row.
        if let browser = BrowserCatalog.info(forBundleID: custom.bundleID) {
            let key = browser.name.lowercased()
            guard RulesStore.hiddenBuiltins().contains(key) else { return false }
            RulesStore.unhideBuiltin(matchKey: key)
            NotificationCenter.default.post(name: .appRulesChanged, object: nil)
            return true
        }
        // A conversation provider (e.g. Teams) manages its app per-conversation,
        // keyed by bundle ID. Adding it as a custom entry would create a
        // duplicate row and, if given a forced language, shadow the provider and
        // disable per-chat memory. Refuse — the provider already lists it — EXCEPT
        // when the user had removed (hidden) it: then re-adding un-hides it.
        if ConversationProviderRegistry.provider(forBundleID: custom.bundleID) != nil {
            let key = custom.name.lowercased()
            guard RulesStore.hiddenBuiltins().contains(key) else { return false }
            RulesStore.unhideBuiltin(matchKey: key)
            NotificationCenter.default.post(name: .appRulesChanged, object: nil)
            return true
        }
        let key = custom.name.lowercased()
        if builtinKeys.contains(key) {
            guard RulesStore.hiddenBuiltins().contains(key) else { return false }
            RulesStore.unhideBuiltin(matchKey: key)
            NotificationCenter.default.post(name: .appRulesChanged, object: nil)
            return true
        }
        guard !all.contains(where: { $0.matchKey == key }) else { return false }
        RulesStore.addCustomApp(custom)
        NotificationCenter.default.post(name: .appRulesChanged, object: nil)
        return true
    }
}

extension Notification.Name {
    // Posted whenever a per-app rule is added, removed, or changed, so live
    // observers (FocusWatcher) can re-sync their per-app focus observers without
    // waiting for the next app switch.
    static let appRulesChanged = Notification.Name("flickey.appRulesChanged")
}

// Persists user overrides and custom apps in UserDefaults.
enum RulesStore {
    private static let overridesKey = "appInputOverrides"
    private static let customKey = "customApps"
    private static let hiddenKey = "hiddenBuiltins"

    // Raw override strings keyed by app matchKey (an input source ID or the
    // AUTO token); interpreted by AppRules.
    static func overrides() -> [String: String] {
        AppDefaults.store.dictionary(forKey: overridesKey) as? [String: String] ?? [:]
    }

    static func set(_ value: String, forMatchKey matchKey: String) {
        var raw = overrides()
        raw[matchKey] = value
        AppDefaults.store.set(raw, forKey: overridesKey)
    }

    static func customApps() -> [CustomApp] {
        guard let data = AppDefaults.store.data(forKey: customKey),
              let apps = try? JSONDecoder().decode([CustomApp].self, from: data)
        else { return [] }
        return apps
    }

    static func addCustomApp(_ app: CustomApp) {
        var apps = customApps()
        apps.append(app)
        if let data = try? JSONEncoder().encode(apps) {
            AppDefaults.store.set(data, forKey: customKey)
        }
    }

    static func removeCustomApp(matchKey: String) {
        let apps = customApps().filter { $0.name.lowercased() != matchKey }
        if let data = try? JSONEncoder().encode(apps) {
            AppDefaults.store.set(data, forKey: customKey)
        }
        clearOverride(matchKey: matchKey)
    }

    static func hiddenBuiltins() -> Set<String> {
        Set(AppDefaults.store.stringArray(forKey: hiddenKey) ?? [])
    }

    static func hideBuiltin(matchKey: String) {
        var hidden = hiddenBuiltins()
        hidden.insert(matchKey)
        AppDefaults.store.set(Array(hidden), forKey: hiddenKey)
        clearOverride(matchKey: matchKey)
    }

    static func unhideBuiltin(matchKey: String) {
        var hidden = hiddenBuiltins()
        hidden.remove(matchKey)
        AppDefaults.store.set(Array(hidden), forKey: hiddenKey)
    }

    private static func clearOverride(matchKey: String) {
        var raw = overrides()
        raw[matchKey] = nil
        AppDefaults.store.set(raw, forKey: overridesKey)
    }
}
