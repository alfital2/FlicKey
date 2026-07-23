import Foundation

// The single switch for "this process is running under UI tests" (the
// -uiTestReset launch argument, set by every XCUITest setUp). Everything that
// behaves differently under UI tests checks HERE, so the test seam in shipping
// code stays one named concept instead of scattered argument checks:
//   • AppDefaults    → throwaway defaults suite (never the user's settings)
//   • TrialManager   → .uitest Keychain item, reset at launch (fresh trial)
//   • LicenseStore   → .uitest Keychain item (never the user's license)
//   • NagController  → silenced
//   • Overlay        → HUDs stay up long enough for XCUITest's ~1 Hz polling
enum UITestMode {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-uiTestReset")
}
