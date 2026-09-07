import XCTest

final class BrowserCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlicKeyBrowserCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        BrowserCatalog.resetApplicationURLsProviderForTesting()
    }

    override func tearDownWithError() throws {
        BrowserCatalog.resetApplicationURLsProviderForTesting()
        try? FileManager.default.removeItem(at: root)
    }

    func testActiveTabSdefUsesAppleScript() throws {
        let bundle = try makeBundle(filename: "Chromium Fork", bundleID: "test.browser.active",
                                    sdef: Data("<property name=\"active tab\"/>".utf8))
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: bundle),
                       .appleScript(tabPhrase: "active tab"))
    }

    func testCurrentTabSdefUsesAppleScriptCaseInsensitively() throws {
        let bundle = try makeBundle(filename: "Safari Fork", bundleID: "test.browser.current",
                                    sdef: Data("<PROPERTY NAME=\"CURRENT TAB\"/>".utf8))
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: bundle),
                       .appleScript(tabPhrase: "current tab"))
    }

    func testMissingOrUnreadableSdefFallsBackToAccessibility() throws {
        let missing = try makeBundle(filename: "Missing", bundleID: "test.browser.missing",
                                     sdef: nil, declaresSdef: true)
        let binary = try makeBundle(filename: "Binary", bundleID: "test.browser.binary",
                                    sdef: Data([0xff, 0x00, 0xfe]))
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: missing), .accessibility)
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: binary), .accessibility)
    }

    func testNoSdefOrInfoPlistFallsBackToAccessibility() throws {
        let ordinary = try makeBundle(filename: "Gecko", bundleID: "test.browser.gecko")
        let empty = root.appendingPathComponent("NoInfo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: ordinary), .accessibility)
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: empty), .accessibility)
    }

    func testSafariGuardSurvivesMissingSdef() throws {
        let safari = try makeBundle(filename: "Safari", bundleID: "com.apple.Safari",
                                    sdef: nil, declaresSdef: true)
        XCTAssertEqual(BrowserCatalog.strategy(forBundleAt: safari),
                       .appleScript(tabPhrase: "current tab"))
    }

    func testDisplayNamePreference() throws {
        let display = try makeBundle(filename: "Filename", bundleID: "test.name.display",
                                     displayName: "Display", bundleName: "Bundle")
        let named = try makeBundle(filename: "Filename2", bundleID: "test.name.bundle",
                                   bundleName: "Bundle")
        let filename = try makeBundle(filename: "Filename3", bundleID: "test.name.filename")
        XCTAssertEqual(BrowserCatalog.displayName(forBundleAt: display), "Display")
        XCTAssertEqual(BrowserCatalog.displayName(forBundleAt: named), "Bundle")
        XCTAssertEqual(BrowserCatalog.displayName(forBundleAt: filename), "Filename3")
    }

    func testInstalledCachesUntilInvalidated() throws {
        let first = try makeBundle(filename: "First", bundleID: "test.browser.first")
        let second = try makeBundle(filename: "Second", bundleID: "test.browser.second")
        var urls = [first]
        var scans = 0
        BrowserCatalog.setApplicationURLsProviderForTesting {
            scans += 1
            return urls
        }
        XCTAssertEqual(BrowserCatalog.installed().map(\.bundleID), ["test.browser.first"])
        urls = [second]
        XCTAssertEqual(BrowserCatalog.installed().map(\.bundleID), ["test.browser.first"])
        XCTAssertEqual(scans, 1)
        BrowserCatalog.invalidate()
        XCTAssertEqual(BrowserCatalog.installed().map(\.bundleID), ["test.browser.second"])
        XCTAssertEqual(scans, 2)
    }

    func testInstalledFiltersAgentsAndCacheArtifactsAndDeduplicates() throws {
        let real = try makeBundle(filename: "Real", bundleID: "test.browser.real")
        let duplicate = try makeBundle(filename: "Duplicate", bundleID: "test.browser.real")
        let agent = try makeBundle(filename: "Agent", bundleID: "test.browser.agent",
                                   extraInfo: ["LSUIElement": true])
        let cacheRoot = root.appendingPathComponent("Library/Caches/tool", isDirectory: true)
        let cached = try makeBundle(filename: "Cached", bundleID: "test.browser.cached",
                                    parent: cacheRoot)
        BrowserCatalog.setApplicationURLsProviderForTesting {
            [real, duplicate, agent, cached]
        }
        XCTAssertEqual(BrowserCatalog.installed().map(\.bundleID), ["test.browser.real"])
    }

    func testInstalledFindsSafariOnADeveloperMac() throws {
        BrowserCatalog.resetApplicationURLsProviderForTesting()
        let browsers = BrowserCatalog.installed()
        guard browsers.contains(where: { $0.bundleID == "com.apple.Safari" }) else {
            throw XCTSkip("LaunchServices did not return Safari on this machine")
        }
    }

    @discardableResult
    private func makeBundle(filename: String,
                            bundleID: String,
                            displayName: String? = nil,
                            bundleName: String? = nil,
                            sdef: Data? = nil,
                            declaresSdef: Bool = false,
                            extraInfo: [String: Any] = [:],
                            parent: URL? = nil) throws -> URL {
        let bundle = (parent ?? root).appendingPathComponent("\(filename).app", isDirectory: true)
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": bundleID]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        if let bundleName { info["CFBundleName"] = bundleName }
        if sdef != nil || declaresSdef { info["OSAScriptingDefinition"] = "browser.sdef" }
        extraInfo.forEach { info[$0.key] = $0.value }
        let plist = try PropertyListSerialization.data(fromPropertyList: info,
                                                       format: .xml,
                                                       options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        if let sdef { try sdef.write(to: resources.appendingPathComponent("browser.sdef")) }
        return bundle
    }
}
