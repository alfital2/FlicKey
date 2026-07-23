import XCTest

// Unit tests for PanelSession — the pure tracker behind FocusWatcher's
// dismiss-restore: which non-activating panels are open, and whether a given
// UI-element destroy is that panel's dismiss (so the underlying app's layout is
// restored). Verifies the actual decision outcome, not just that it runs.
final class PanelSessionTests: XCTestCase {

    // Summoning a panel (forced while NOT frontmost) opens a session, and the
    // destroy that clears the focused element is recognized as its dismiss.
    func testSummonThenDismiss() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: false)
        XCTAssertTrue(s.hasOpenPanel(pid: 100))
        XCTAssertTrue(s.destroyed(pid: 100, keyboardFocusLost: true))
        XCTAssertFalse(s.hasOpenPanel(pid: 100), "dismiss consumes the session")
    }

    // A normal activation (forced WHILE frontmost) is not a panel — no session,
    // so a later destroy never triggers a restore.
    func testFrontmostForceOpensNoSession() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: true)
        XCTAssertFalse(s.hasOpenPanel(pid: 100))
        XCTAssertFalse(s.destroyed(pid: 100, keyboardFocusLost: true))
    }

    // Element churn while the panel is still open (focused element present) must
    // NOT be treated as a dismiss — the session stays open until it's really gone.
    func testChurnWhileOpenIsNotDismiss() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: false)
        XCTAssertFalse(s.destroyed(pid: 100, keyboardFocusLost: false))
        XCTAssertTrue(s.hasOpenPanel(pid: 100), "still open after churn")
        XCTAssertTrue(s.destroyed(pid: 100, keyboardFocusLost: true), "then the real dismiss fires")
    }

    // A destroy for an app with no open session is ignored.
    func testDestroyWithoutSessionIgnored() {
        var s = PanelSession()
        XCTAssertFalse(s.destroyed(pid: 100, keyboardFocusLost: true))
    }

    // The dismiss is one-shot: a second destroy after it does not re-trigger.
    func testDismissIsOneShot() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: false)
        XCTAssertTrue(s.destroyed(pid: 100, keyboardFocusLost: true))
        XCTAssertFalse(s.destroyed(pid: 100, keyboardFocusLost: true))
    }

    // Sessions are tracked per-pid and don't bleed across apps.
    func testSessionsAreIndependentPerApp() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: false)
        s.forced(pid: 200, appWasFrontmost: false)
        XCTAssertTrue(s.destroyed(pid: 100, keyboardFocusLost: true))
        XCTAssertFalse(s.hasOpenPanel(pid: 100))
        XCTAssertTrue(s.hasOpenPanel(pid: 200), "the other app's session is untouched")
    }

    // forget() (app terminated / no longer observed) clears an open session.
    func testForgetClearsSession() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: false)
        s.forget(pid: 100)
        XCTAssertFalse(s.hasOpenPanel(pid: 100))
        XCTAssertFalse(s.destroyed(pid: 100, keyboardFocusLost: true))
    }

    // A normal activation of an app that had an open panel clears the stale
    // session (it's now a foreground window, not a non-activating panel).
    func testFrontmostForceClearsStaleSession() {
        var s = PanelSession()
        s.forced(pid: 100, appWasFrontmost: false)
        s.forced(pid: 100, appWasFrontmost: true)
        XCTAssertFalse(s.hasOpenPanel(pid: 100))
    }
}
