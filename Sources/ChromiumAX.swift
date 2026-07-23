import ApplicationServices

// Coaxing a Chromium/WebView2/Electron app (Microsoft Teams) into building — and
// rebuilding — its Accessibility tree so we can read the focused window title.
//
// Chromium builds its AX tree lazily and TEARS IT DOWN when a tab/window is
// hidden: content/browser/accessibility/browser_accessibility_state_impl.cc arms
// an "AccessibilityDisabler" (~5 min) on hide that empties the a11y mode. On
// reveal it only cancels the (already-fired) disabler — it does NOT re-enable —
// so after Teams sits in the background the tree is gone: kAXTitle reads fail and
// no kAXTitleChanged fires. Worse, setting AXManualAccessibility=true again when
// it's still nominally "on" is a guarded no-op, so a plain re-assert can't revive
// it. The only reliable revive is to TOGGLE the enable flag false→true, which
// re-creates the scoped mode and re-propagates it to the revealed window.
//
// (Real Chrome/Edge honor AXEnhancedUserInterface; Electron-style apps honor
// AXManualAccessibility. Teams responds to AXManualAccessibility in the field, and
// it avoids AXEnhancedUserInterface's window-resize/animation side effects, so we
// use it exclusively.)
enum ChromiumAX {

    private static let manualAccessibility = "AXManualAccessibility" as CFString

    // Ask the app to build its AX tree now, and cap how long any AX call to it can
    // block us (default is 6s; an unresponsive Teams must not stall the poll).
    static func enable(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        AXUIElementSetAttributeValue(app, manualAccessibility, kCFBooleanTrue)
        if DebugLog.enabled { DebugLog.recovery.notice("enable AXManualAccessibility (pid \(pid, privacy: .public))") }
    }

    // Force a rebuild after Chromium tore the tree down: toggle false→true. The
    // tree materializes asynchronously (~2s, Chromium debounces the enable), so
    // callers keep polling and pick it up once it's back.
    static func forceRebuild(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, manualAccessibility, kCFBooleanFalse)
        if DebugLog.enabled { DebugLog.recovery.notice("forceRebuild: toggle false→true (pid \(pid, privacy: .public))") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AXUIElementSetAttributeValue(app, manualAccessibility, kCFBooleanTrue)
        }
    }
}
