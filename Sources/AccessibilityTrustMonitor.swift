import AppKit
import ApplicationServices

// AX trust has a query API but no documented permission-change notification.
// Keep the transition logic pure/testable, and re-query on meaningful system
// lifecycle events instead of polling on a timer.
struct AccessibilityTrustStateTracker {
    private(set) var current: Bool?

    mutating func accept(_ trusted: Bool) -> Bool? {
        guard current != trusted else { return nil }
        current = trusted
        return trusted
    }
}

enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// Checks at startup, whenever any application becomes frontmost, when FlicKey
// itself becomes active, and after session wake/reactivation. A grant made in
// System Settings is therefore picked up when the user returns to work, while a
// later revocation is detected on the next focus transition. No periodic timer.
final class AccessibilityTrustMonitor {
    var onChange: ((Bool) -> Void)?
    var onCheck: ((Bool) -> Void)?

    private var state = AccessibilityTrustStateTracker()
    private var workspaceTokens: [NSObjectProtocol] = []
    private var appToken: NSObjectProtocol?

    var isTrusted: Bool { state.current ?? AccessibilityAccess.isTrusted }

    func start() {
        guard workspaceTokens.isEmpty, appToken == nil else { return }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceTokens.append(workspace.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.check()
                })
        }
        appToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in self?.check() }

        check()
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { workspace.removeObserver($0) }
        workspaceTokens.removeAll()
        if let appToken { NotificationCenter.default.removeObserver(appToken) }
        appToken = nil
    }

    private func check() {
        let trusted = AccessibilityAccess.isTrusted
        onCheck?(trusted)
        guard let transition = state.accept(trusted) else { return }
        NotificationCenter.default.post(name: .accessibilityTrustChanged,
                                        object: nil,
                                        userInfo: ["trusted": transition])
        onChange?(transition)
    }

    deinit { stop() }
}

extension Notification.Name {
    static let accessibilityTrustChanged = Notification.Name("flickey.accessibilityTrustChanged")
}
