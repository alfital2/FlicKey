import Foundation

// Pure tracker for non-activating-panel sessions, extracted from FocusWatcher so
// the dismiss-restore decision can be unit-tested without AX / NSWorkspace (the
// same pure-core/plumbing split as DoubleTapStateMachine↔DoubleTapDetector and
// FocusGate↔FocusWatcher).
//
// A forced app that grabs the keyboard WHILE NOT FRONTMOST did so via a
// non-activating panel (e.g. Ghostty's quick terminal). Such a panel posts no
// event when dismissed, but its app fires kAXUIElementDestroyed and, once the
// panel is gone, the app stops owning the system-wide keyboard focus. This tracks
// which apps currently have an open panel so a later destroy that coincides with
// lost keyboard focus is recognized as that panel's dismiss, the cue to restore
// the underlying app's layout. Element churn while the panel is still open
// (keyboard focus retained) must NOT be mistaken for a dismiss, or we'd switch the
// layout out from under the user mid-typing.
struct PanelSession {

    private var open: Set<pid_t> = []

    // A forced switch happened for `pid`. If the app was NOT frontmost it took
    // the keyboard via a non-activating panel → open a session. If it WAS
    // frontmost this was a normal activation (no panel); clear any stale session.
    mutating func forced(pid: pid_t, appWasFrontmost: Bool) {
        if appWasFrontmost { open.remove(pid) } else { open.insert(pid) }
    }

    // A UI element of `pid` was destroyed. Returns true iff this is the dismiss of
    // a tracked panel (the app has now lost the system keyboard focus), consuming
    // the session. A destroy while the app still owns keyboard focus (churn while
    // open) leaves the session intact and returns false.
    mutating func destroyed(pid: pid_t, keyboardFocusLost: Bool) -> Bool {
        guard open.contains(pid), keyboardFocusLost else { return false }
        open.remove(pid)
        return true
    }

    // Whether `pid` currently has an open panel — a cheap pre-check so callers
    // can skip the Accessibility read for destroys that can't be a dismiss.
    func hasOpenPanel(pid: pid_t) -> Bool { open.contains(pid) }

    // The app terminated / is no longer observed.
    mutating func forget(pid: pid_t) { open.remove(pid) }
}
