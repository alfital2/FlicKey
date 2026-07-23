import AppKit
import ApplicationServices

// Reads the active tab's URL from a scriptable browser via AppleScript and
// reduces it to a stable domain key (e.g. "bankleumi.co.il"). Used by
// TabMemory to remember a preferred input language per website.
//
// The first call targeting a given browser triggers the macOS Automation
// permission prompt ("…wants to control Safari"). Firefox isn't reliably
// scriptable, so it returns nil there.
enum BrowserURLReader {

    // What the active tab is, from TabMemory's point of view.
    enum TabState: Equatable {
        case site(String)   // a real website, keyed by its domain
        case newTab         // a blank/new tab waiting for input (its own preference)
        case unreadable     // couldn't determine — keep whatever tab was prior
    }

    // The outcome of asking a browser for its active tab's URL. Crucially, a
    // browser can ANSWER with "no URL" for a blank tab (Safari returns AppleScript
    // `missing value`, i.e. a nil/empty string) — that is a definite blank tab,
    // NOT a failure to read. Only a script ERROR is `.failed`.
    enum ReadResult: Equatable {
        case value(String)   // a URL string
        case blank           // script ran, but the tab has no URL → a blank tab
        case failed          // couldn't run the script at all
    }

    // Browsers we can ask for a URL, by display name. Chromium-based browsers
    // share the "active tab of front window" vocabulary; Safari differs.
    private static let safari = "Safari"
    private static let unsupported: Set<String> = ["Firefox"]

    static func state(forBrowserNamed name: String) -> TabState {
        state(from: fetchURL(browserNamed: name))
    }

    // Map a read result to a tab state. `.failed` keeps the prior tab (never reset
    // a real site on a transient glitch); `.blank` (no URL) is a new tab; a value
    // is a real site unless it is a browser's internal new-tab page. Pure, so the
    // whole missing-value-vs-error distinction is unit-tested.
    static func state(from result: ReadResult) -> TabState {
        switch result {
        case .failed: return .unreadable
        case .blank: return .newTab
        case .value(let urlString): return classify(urlString)
        }
    }

    // Classify a non-empty URL string a browser returned.
    static func classify(_ urlString: String) -> TabState {
        if isNewTabURL(urlString) { return .newTab }
        if let host = host(from: urlString) { return .site(host) }
        return .unreadable   // readable but not a site we track → keep prior
    }

    // The internal URLs browsers show for a fresh, empty tab across engines. An
    // empty string is Safari's blank start page; the schemes cover Chrome, Edge,
    // Brave, Arc and the about: family.
    static func isNewTabURL(_ urlString: String) -> Bool {
        let s = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return true }
        let newTabPrefixes = [
            "chrome://newtab", "chrome://new-tab", "chrome-search://",
            "edge://newtab", "brave://newtab",
            "about:blank", "about:newtab", "about:home",
            "favorites://",
        ]
        return newTabPrefixes.contains { s.hasPrefix($0) }
    }

    // MARK: - AppleScript

    private static func fetchURL(browserNamed name: String) -> ReadResult {
        guard !unsupported.contains(name) else { return .failed }

        let tabPhrase = (name == safari) ? "current tab" : "active tab"
        // Read the URL of the window the user is actually FOCUSED on. With more
        // than one browser window open, AppleScript's "front window" can resolve
        // to a DIFFERENT window than the one with keyboard focus, so FlicKey
        // would read the wrong site (e.g. a separate Netflix window) for every
        // tab. The focused window's title (via Accessibility) uniquely names the
        // right AppleScript window. Fall back to "front window" only if the scoped
        // read ERRORS (a blank tab answering with no URL is a valid read).
        if let title = focusedWindowTitle(ofAppNamed: name) {
            let escaped = title.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
            let scoped = "tell application \"\(name)\" to get URL of \(tabPhrase) of (first window whose name is \"\(escaped)\")"
            let result = run(scoped)
            if result != .failed { return result }
        }
        return run("tell application \"\(name)\" to get URL of \(tabPhrase) of front window")
    }

    // Compiled scripts, keyed by source. NSAppleScript compiles on first execute
    // and keeps the compiled form, so reusing the object turns repeat reads (the
    // constant fallback script, and revisits of a same-titled window) from
    // compile+run into run-only. Bounded: the scoped script embeds the window
    // title, so distinct sources accumulate; reset rather than grow. Main-thread
    // only, like every caller in this file.
    private static var compiledScripts: [String: NSAppleScript] = [:]
    private static let compiledScriptsCap = 16

    private static func run(_ appleScript: String) -> ReadResult {
        let script: NSAppleScript
        if let cached = compiledScripts[appleScript] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: appleScript) else { return .failed }
            if compiledScripts.count >= compiledScriptsCap { compiledScripts.removeAll() }
            compiledScripts[appleScript] = fresh
            script = fresh
        }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        guard error == nil else { return .failed }
        // The script ran. A blank tab answers with AppleScript `missing value`
        // (nil stringValue) or an empty string — that is a definite blank tab, not
        // a failure, so it must NOT fall back to the front window or keep the prior
        // site.
        guard let url = output.stringValue, !url.isEmpty else { return .blank }
        return .value(url)
    }

    // The title of the browser's keyboard-focused window, via Accessibility —
    // used to disambiguate which window to read when several are open.
    private static func focusedWindowTitle(ofAppNamed name: String) -> String? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })
        else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success
        else { return nil }
        return titleRef as? String
    }

    // MARK: - Domain extraction

    // Reduce a full URL to its registrable host, dropping a leading "www.".
    static func host(from urlString: String) -> String? {
        guard let host = URLComponents(string: urlString)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
