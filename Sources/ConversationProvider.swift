import AppKit
import ApplicationServices

// A ConversationProvider knows how to read "which conversation is the user in
// right now" for one app (or family of apps). It is the extension point for
// app-specific per-conversation input memory: to support a new app, add a
// provider and register it — nothing else in the pipeline changes.
//
// The shape deliberately mirrors how the browser per-site feature already
// works (watch the window title, derive a stable key), so the same
// input-source-monitoring and namespaced-memory infrastructure is reused
// rather than reinvented.
// What the provider can tell about the app's current context. Three cases
// because they demand DIFFERENT reactions from the memory controller: a real
// non-conversation view must clear the active key (so a layout change in
// Activity/Calendar isn't saved under the last chat), but a transient AX read
// failure must NOT — Teams retitles in stages when switching chats, and
// treating a blip as "left the conversation" silently drops the user's next
// layout change (their per-person language then never gets remembered).
enum ConversationContext: Equatable {
    case conversation(String)   // an open conversation and its stable key
    case notAConversation       // a readable title that isn't an open chat
    case unreadable             // transient AX failure — keep the prior state
}

protocol ConversationProvider {

    // Stable namespace under which this provider's memory is stored, e.g.
    // "teams". Must be unique per provider and never change once shipped
    // (it keys persisted user data).
    var namespace: String { get }

    // Display name for the per-app settings list (e.g. "Microsoft Teams").
    var displayName: String { get }

    // Bundle IDs of the app(s) this provider handles. The first installed one
    // is used for the settings list's icon and installed check.
    var bundleIDs: [String] { get }

    // The current conversation context within the app. A conversation key only
    // needs to be *stable* and *unique per conversation*; it is never shown to
    // the user, so cosmetic suffixes are fine to keep as long as they're stable.
    func context(pid: pid_t) -> ConversationContext
}

extension ConversationProvider {
    func handles(bundleID: String) -> Bool { bundleIDs.contains(bundleID) }

    // The title of the app's focused window, read with a single cheap AX attribute
    // fetch, or nil if there's no focused window or title. Providers that key on the
    // window title share this instead of each copying the same read.
    func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let s = title as? String, !s.isEmpty else { return nil }
        return s
    }
}

// Registry of the providers FlicKey knows about. Kept tiny and static; adding
// an app is a one-line append here plus the provider file.
enum ConversationProviderRegistry {

    static let all: [ConversationProvider] = [
        TeamsConversationProvider(),
        SlackConversationProvider(),
    ]

    static func provider(forBundleID bundleID: String?) -> ConversationProvider? {
        guard let bundleID else { return nil }
        return all.first { $0.handles(bundleID: bundleID) }
    }

    // Installed conversation-provider apps, for the per-app settings list:
    // (display name, the installed bundle ID, namespace). A provider whose app
    // isn't installed is skipped.
    static func installedApps() -> [(displayName: String, bundleID: String, namespace: String)] {
        all.compactMap { provider in
            guard let bundleID = provider.bundleIDs.first(where: {
                !$0.isEmpty && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }) else { return nil }
            return (provider.displayName, bundleID, provider.namespace)
        }
    }
}
