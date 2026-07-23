import Foundation

// Pure decision for whether a forced app's Accessibility focus event should
// trigger a layout switch — extracted from FocusWatcher so it can be unit-tested
// without AX / NSWorkspace (the same pure-core/plumbing split as
// DoubleTapStateMachine↔DoubleTapDetector and AppRouting↔AppWatcher).
//
// FocusWatcher observes per-app focus notifications on apps that have a FORCED
// input source. Most fire exactly when we want (a non-activating panel like
// Ghostty's quick terminal grabs the keyboard). Two kinds must be filtered out:
//
//   1. Burst — a single summon posts several AX notifications within a few ms
//      (FocusedWindow + FocusedUIElement + MainWindow…). Only the first acts;
//      the rest are coalesced so we don't thrash the controllers.
//
//   2. Switch-away — when the user switches FROM a forced app TO another app,
//      that other app's activation is already handled by AppWatcher. The forced
//      app being left could, in principle, emit a focus event as it loses key
//      status; acting on it would re-assert the left app's layout and tear down
//      the new app's per-site/per-conversation controller. So we suppress a
//      focus event that lands right after a DIFFERENT app activated.
//
//      Keying on activation (not the forced app's own deactivation) is
//      deliberate and makes the guard robust to notification ordering: the SAME
//      didActivate(B) both arms the guard and — via AppWatcher — establishes B's
//      controller and layout. If B's activation is processed BEFORE this focus
//      event, the event is suppressed. If it's processed AFTER, the (un-guarded)
//      force runs first but is immediately corrected when B's activation lands.
//      Either ordering ends correct. A non-activating panel summon posts NO
//      activation, so summons themselves are never suppressed.
enum FocusGate {

    // Coalesce the multi-notification burst from a single focus change. Sized a
    // bit above the observed ~15ms storm, well below a deliberate re-summon.
    static let burstWindow: TimeInterval = 0.06
    // Treat a focus event this soon after another app activated as the tail of a
    // normal app switch, not a panel summon.
    static let activationGuard: TimeInterval = 0.20

    // - sinceLastForce:    seconds since this app last triggered a forced switch.
    // - sinceActivation:   seconds since the most recent app activation (any app).
    // - activationWasSelf: was that most recent activation THIS app? A normal
    //   click-to-front of the forced app itself must NOT be suppressed.
    static func shouldForce(
        sinceLastForce: TimeInterval,
        sinceActivation: TimeInterval,
        activationWasSelf: Bool,
        burstWindow: TimeInterval = FocusGate.burstWindow,
        activationGuard: TimeInterval = FocusGate.activationGuard
    ) -> Bool {
        if sinceLastForce < burstWindow { return false }
        if sinceActivation < activationGuard && !activationWasSelf { return false }
        return true
    }
}
