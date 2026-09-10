import AppKit

// What input an app should use: a specific macOS input source, or AUTO
// (browsers only — input is learned/applied per website at runtime).
enum InputRule: Equatable {
    case source(String) // input source ID, e.g. "com.apple.keylayout.Hebrew-PC"
    case auto
    case undefined

    var sourceID: String? { if case .source(let id) = self { return id }; return nil }
    var isAuto: Bool { if case .auto = self { return true }; return false }
    var isUndefined: Bool { if case .undefined = self { return true }; return false }

    var fallbackSymbol: String { isAuto ? "globe" : "keyboard" }

    // Persisted string form.
    static let autoToken = "__auto__"
    static let undefinedToken = "__undefined__"
    var storageValue: String {
        if isAuto { return Self.autoToken }
        if isUndefined { return Self.undefinedToken }
        return sourceID ?? ""
    }
    init?(storage: String) {
        if storage == Self.autoToken { self = .auto }
        else if storage == Self.undefinedToken { self = .undefined }
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
    let isImported: Bool  // shown because "Import all my apps" is enabled
    let kind: AppKind

    var isBrowser: Bool { kind == .browser }
    var isConversationApp: Bool { kind == .conversation }
    // Only ordinary app rows learn one app-wide preference. Browsers and chat
    // apps own finer-grained memory (per site / per conversation), so learning
    // them here would accidentally flatten those behaviors into one rule.
    var learnsAppPreference: Bool { kind == .normal }
    var matchKey: String { name.lowercased() }
}

// A user-added app, persisted in UserDefaults.
struct CustomApp: Codable {
    let name: String
    let bundleID: String
}

// Single source of truth for per-app input rules, shared by AppWatcher (to act)
// and the preferences window (to display + edit). Ordinary apps are never
// hardcoded: they are added explicitly or discovered when the user enables
// "Import all my apps". Discovered ordinary apps default to .undefined, which
// deliberately leaves the current input source untouched.
enum AppRules {

    private static var installedAppsProvider: () -> [CustomApp] = AppFinder.installedApps

    // Older releases knew ordinary apps through a hardcoded catalog, so an
    // explicitly chosen source could exist without a persisted app identity.
    // Recover only those real user choices by matching their saved name keys to
    // currently installed apps. Untouched old defaults had no override and are
    // intentionally not migrated.
    private static func migrateConfiguredOrdinaryApps() {
        let overrides = RulesStore.overrides()
        guard !overrides.isEmpty else { return }

        let existing = RulesStore.customApps()
        var names = Set(existing.map { normalizedName($0.name) })
        var bundleIDs = Set(existing.map { $0.bundleID.lowercased() })

        for app in installedAppsProvider() {
            let key = normalizedName(app.name)
            let bundleKey = app.bundleID.lowercased()
            guard overrides[key] != nil,
                  !key.isEmpty, !bundleKey.isEmpty,
                  !names.contains(key), !bundleIDs.contains(bundleKey),
                  BrowserCatalog.info(forBundleID: app.bundleID) == nil,
                  ConversationProviderRegistry.provider(forBundleID: app.bundleID) == nil
            else { continue }

            RulesStore.addCustomApp(app)
            names.insert(key)
            bundleIDs.insert(bundleKey)
        }
    }

    private static var builtinKeys: Set<String> {
        Set(BrowserCatalog.installed().map { $0.name.lowercased() })
    }

    // Built-ins + custom apps, with persisted overrides applied. Built-ins the
    // user removed are hidden; uninstalled browsers are skipped.
    static var all: [AppRule] {
        migrateConfiguredOrdinaryApps()
        let overrides = RulesStore.overrides()
        let hidden = RulesStore.hiddenBuiltins()
        var seen = Set<String>()
        var result: [AppRule] = []
        let browsers = BrowserCatalog.installed()
        let browserBundleIDs = Set(browsers.map { $0.bundleID.lowercased() })
        let customApps = RulesStore.customApps()
        let customBundleIDs = Set(customApps.map { $0.bundleID.lowercased() })

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
                rule: resolveRule(overrides[key], defaultRule: .auto),
                isCustom: false,
                isImported: false,
                kind: .browser
            ))
        }

        for custom in customApps {
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
                rule: resolveRule(overrides[key], defaultRule: .undefined),
                isCustom: true,
                isImported: false,
                kind: .normal
            ))
        }

        if RulesStore.importAllAppsEnabled() {
            for imported in installedAppsProvider() {
                let key = normalizedName(imported.name)
                let bundleKey = imported.bundleID.lowercased()
                guard !key.isEmpty, !bundleKey.isEmpty,
                      imported.bundleID != Bundle.main.bundleIdentifier,
                      !seen.contains(key),
                      !customBundleIDs.contains(bundleKey),
                      !browserBundleIDs.contains(bundleKey),
                      ConversationProviderRegistry.provider(forBundleID: imported.bundleID) == nil,
                      !hidden.contains(key) else { continue }
                seen.insert(key)
                result.append(AppRule(
                    name: imported.name,
                    bundleID: imported.bundleID,
                    rule: resolveRule(overrides[key], defaultRule: .undefined),
                    isCustom: false,
                    isImported: true,
                    kind: .normal
                ))
            }
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
                rule: resolveRule(overrides[key], defaultRule: .auto),
                isCustom: false,
                isImported: false,
                kind: .conversation
            ))
        }
        return result
    }

    // An explicit override wins. Browsers/conversation apps pass .auto;
    // ordinary apps pass .undefined so merely listing one never changes layout.
    private static func resolveRule(_ override: String?, defaultRule: InputRule) -> InputRule {
        if let override, let rule = InputRule(storage: override) { return rule }
        return defaultRule
    }

    // All apps the user can configure, sorted alphabetically. Browsers get an
    // AUTO (per-site) option; other apps pick any one enabled input source.
    static var editable: [AppRule] {
        all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Effective rule for an already-normalized (lowercased) app name.
    static func rule(forNormalizedName name: String) -> InputRule? {
        appRule(forBundleID: nil, normalizedName: name)?.rule
    }

    // Prefer stable bundle identity for a running app. Name fallback preserves
    // custom/built-in behavior when an old or unusual app has no bundle ID.
    static func rule(for app: NSRunningApplication) -> InputRule? {
        appRule(for: app)?.rule
    }

    static func rule(forBundleID bundleID: String?, normalizedName name: String) -> InputRule? {
        appRule(forBundleID: bundleID, normalizedName: name)?.rule
    }

    // Full matched row for callers that need its identity/kind in addition to
    // the effective input rule (notably AppWatcher when learning a preference).
    static func appRule(for app: NSRunningApplication) -> AppRule? {
        appRule(forBundleID: app.bundleIdentifier,
                normalizedName: normalizedName(app.localizedName))
    }

    static func appRule(forBundleID bundleID: String?, normalizedName name: String) -> AppRule? {
        let rules = all
        if let bundleID,
           let match = rules.first(where: {
               $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame
           }) {
            return match
        }
        return name.isEmpty ? nil : rules.first { $0.matchKey == name }
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
        if rule.isUndefined {
            RulesStore.clearOverride(matchKey: app.matchKey)
        } else {
            if app.isImported,
               !RulesStore.customApps().contains(where: {
                   $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame
               }) {
                RulesStore.addCustomApp(CustomApp(name: app.name, bundleID: app.bundleID))
            }
            RulesStore.set(rule.storageValue, forMatchKey: app.matchKey)
        }
        NotificationCenter.default.post(name: .appRulesChanged, object: nil)
    }

    // Called for a real user input-source change while an ordinary app is
    // active. The first change turns an imported `Not defined` row into a
    // persistent app preference; subsequent changes replace that preference.
    // Duplicate notifications (including our own forced switch) are ignored.
    static func rememberSource(_ sourceID: String, for app: AppRule) {
        guard app.learnsAppPreference, app.rule.sourceID != sourceID else { return }
        setRule(.source(sourceID), for: app)
    }

    static var importsAllApps: Bool { RulesStore.importAllAppsEnabled() }

    static func setImportsAllApps(_ enabled: Bool) {
        RulesStore.setImportAllAppsEnabled(enabled)
        NotificationCenter.default.post(name: .appRulesChanged, object: nil)
    }

    #if DEBUG
    static func setInstalledAppsProviderForTesting(_ provider: @escaping () -> [CustomApp]) {
        installedAppsProvider = provider
    }

    static func resetInstalledAppsProviderForTesting() {
        installedAppsProvider = AppFinder.installedApps
    }
    #endif

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
    private static let importAllKey = "importAllApps"

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

    static func importAllAppsEnabled() -> Bool {
        AppDefaults.store.bool(forKey: importAllKey)
    }

    static func setImportAllAppsEnabled(_ enabled: Bool) {
        AppDefaults.store.set(enabled, forKey: importAllKey)
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

    static func clearOverride(matchKey: String) {
        var raw = overrides()
        raw[matchKey] = nil
        AppDefaults.store.set(raw, forKey: overridesKey)
    }
}
