import AppKit

private final class SdefCapabilityParser: NSObject, XMLParserDelegate {
    private(set) var hasActiveTabProperty = false
    private(set) var hasCurrentTabProperty = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName.caseInsensitiveCompare("property") == .orderedSame,
              let name = attributeDict.first(where: {
                  $0.key.caseInsensitiveCompare("name") == .orderedSame
              })?.value.lowercased() else { return }
        if name == "active tab" { hasActiveTabProperty = true }
        if name == "current tab" { hasCurrentTabProperty = true }
    }
}

// Stable identity for the browser TabMemory is currently following. Display
// names are user-facing and can be localized or renamed; the bundle identifier
// selects the read strategy/Apple Event target, and the pid selects its AX tree.
struct BrowserTarget: Equatable {
    let name: String
    let bundleID: String
    let pid: pid_t
}

enum TabReadStrategy: Equatable {
    case appleScript(tabPhrase: String)
    case accessibility
}

struct BrowserInfo: Equatable {
    let name: String
    let bundleID: String
    let strategy: TabReadStrategy
}

// Discovers browsers through LaunchServices instead of maintaining an engine or
// product-name allowlist. The strategy is a capability probe over the bundle:
// browsers that publish AppleScript tab vocabulary use it; every other browser
// uses the public Accessibility URL exposed by its selected web area.
//
// LaunchServices can retain development helpers and non-browser URL handlers.
// We discard background agents plus cache-only app copies, then deduplicate by
// bundle ID. This keeps real downloaded/installed browsers discoverable without
// listing Hammerspoon or Playwright/Puppeteer cache artifacts as browsers.
enum BrowserCatalog {

    private struct Cache {
        let createdAt: TimeInterval
        let browsers: [BrowserInfo]
    }

    private static let cacheTTL: TimeInterval = 60
    private static let sdefReadLimit = 256 * 1_024
    private static let lock = NSLock()
    private static var cache: Cache?
    private static var applicationURLsProvider: () -> [URL] = {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
    }

    static func installed() -> [BrowserInfo] {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let cached = cache, now - cached.createdAt < cacheTTL {
            lock.unlock()
            return cached.browsers
        }
        let provider = applicationURLsProvider
        lock.unlock()

        let discovered = discover(from: provider())
        lock.lock()
        cache = Cache(createdAt: now, browsers: discovered)
        lock.unlock()
        return discovered
    }

    static func info(forBundleID bundleID: String) -> BrowserInfo? {
        installed().first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    static func invalidate() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    // Pure bundle inspection seams used by the unit suite.
    static func strategy(forBundleAt url: URL) -> TabReadStrategy {
        let metadata = infoDictionary(at: url)
        if let definition = metadata?["OSAScriptingDefinition"] as? String,
           !definition.isEmpty {
            let sdefURL = url.appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(definition)
            if let handle = try? FileHandle(forReadingFrom: sdefURL) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: sdefReadLimit) {
                    let capabilities = SdefCapabilityParser()
                    let parser = XMLParser(data: data)
                    parser.delegate = capabilities
                    _ = parser.parse()
                    if capabilities.hasActiveTabProperty {
                        return .appleScript(tabPhrase: "active tab")
                    }
                    if capabilities.hasCurrentTabProperty {
                        return .appleScript(tabPhrase: "current tab")
                    }
                }
            }
        }
        if (metadata?["CFBundleIdentifier"] as? String) == "com.apple.Safari" {
            return .appleScript(tabPhrase: "current tab")
        }
        return .accessibility
    }

    static func displayName(forBundleAt url: URL) -> String {
        let metadata = infoDictionary(at: url)
        if let bundleID = metadata?["CFBundleIdentifier"] as? String,
           let runningName = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
           })?.localizedName,
           !runningName.isEmpty {
            return runningName
        }
        // object(forInfoDictionaryKey:) consults localized InfoPlist.strings;
        // the raw dictionary below does not. This keeps the catalog name aligned
        // with NSRunningApplication.localizedName before the browser is running.
        let localizedBundle = Bundle(url: url)
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = localizedBundle?.object(forInfoDictionaryKey: key) as? String,
               !name.isEmpty { return name }
            if let name = metadata?[key] as? String, !name.isEmpty { return name }
        }
        let filename = FileManager.default.displayName(atPath: url.path)
        return filename.hasSuffix(".app") ? String(filename.dropLast(4)) : filename
    }

    // MARK: - Test control

    static func setApplicationURLsProviderForTesting(_ provider: @escaping () -> [URL]) {
        lock.lock()
        applicationURLsProvider = provider
        cache = nil
        lock.unlock()
    }

    static func resetApplicationURLsProviderForTesting() {
        lock.lock()
        applicationURLsProvider = {
            guard let probe = URL(string: "https://example.com") else { return [] }
            return NSWorkspace.shared.urlsForApplications(toOpen: probe)
        }
        cache = nil
        lock.unlock()
    }

    // MARK: - Discovery

    private static func discover(from urls: [URL]) -> [BrowserInfo] {
        var byBundleID: [String: (url: URL, info: BrowserInfo)] = [:]
        for url in urls {
            guard let metadata = infoDictionary(at: url),
                  let bundleID = metadata["CFBundleIdentifier"] as? String,
                  !bundleID.isEmpty,
                  isBrowserCandidate(url: url, metadata: metadata) else { continue }
            let info = BrowserInfo(name: displayName(forBundleAt: url),
                                   bundleID: bundleID,
                                   strategy: strategy(forBundleAt: url))
            let key = bundleID.lowercased()
            if let existing = byBundleID[key], installationRank(existing.url) >= installationRank(url) {
                continue
            }
            byBundleID[key] = (url, info)
        }
        return byBundleID.values.map(\.info).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func infoDictionary(at bundleURL: URL) -> [String: Any]? {
        let url = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return raw as? [String: Any]
    }

    private static func isBrowserCandidate(url: URL, metadata: [String: Any]) -> Bool {
        if metadata["LSUIElement"] as? Bool == true || metadata["LSBackgroundOnly"] as? Bool == true {
            return false
        }
        let path = url.standardizedFileURL.path.lowercased()
        if path.contains("/library/caches/") || path.contains("/.cache/") { return false }
        return true
    }

    private static func installationRank(_ url: URL) -> Int {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/Applications/") || path.contains("/System/Applications/") { return 3 }
        if path.contains("/Applications/") { return 2 }
        return 1
    }
}

// Owns catalog invalidation for the running app. Changes are broadcast so an
// already-open Apps settings pane can rebuild its discovered Browsers section.
final class BrowserCatalogObserver {
    private var workspaceTokens: [NSObjectProtocol] = []
    private var rulesToken: NSObjectProtocol?

    func start() {
        guard workspaceTokens.isEmpty, rulesToken == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didMountNotification,
                     NSWorkspace.didUnmountNotification] {
            workspaceTokens.append(workspace.addObserver(
                forName: name, object: nil, queue: .main) { _ in
                    BrowserCatalog.invalidate()
                    AppFinder.invalidateInstalledApps()
                    NotificationCenter.default.post(name: .browserCatalogChanged, object: nil)
                })
        }
        rulesToken = NotificationCenter.default.addObserver(
            forName: .appRulesChanged, object: nil, queue: .main) { _ in
                BrowserCatalog.invalidate()
            }
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { workspace.removeObserver($0) }
        workspaceTokens.removeAll()
        if let rulesToken { NotificationCenter.default.removeObserver(rulesToken) }
        rulesToken = nil
    }

    deinit { stop() }
}

extension Notification.Name {
    static let browserCatalogChanged = Notification.Name("flickey.browserCatalogChanged")
}
