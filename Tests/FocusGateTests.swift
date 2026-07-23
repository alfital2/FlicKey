import XCTest

// Unit tests for FocusGate — the pure decision behind FocusWatcher: should a
// forced app's Accessibility focus event trigger a layout switch? Two filters:
// burst coalescing and the switch-away guard (keyed on a different app's recent
// activation).
final class FocusGateTests: XCTestCase {

    private func decide(force: TimeInterval, activation: TimeInterval, wasSelf: Bool) -> Bool {
        FocusGate.shouldForce(
            sinceLastForce: force,
            sinceActivation: activation,
            activationWasSelf: wasSelf,
            burstWindow: 0.06,
            activationGuard: 0.20)
    }

    // A panel summon: no recent activation, not a burst → act.
    func testSummonForces() {
        XCTAssertTrue(decide(force: 5, activation: 5, wasSelf: false))
    }

    // First-ever focus for an app (no prior force, no prior activation) → act.
    func testFirstEverForces() {
        XCTAssertTrue(decide(force: .infinity, activation: .infinity, wasSelf: false))
    }

    // The multi-notification burst from a single summon (FocusedWindow +
    // FocusedUIElement + MainWindow within a few ms) collapses to one action.
    func testBurstCoalesced() {
        XCTAssertFalse(decide(force: 0.02, activation: 5, wasSelf: false))
    }

    // Switching to ANOTHER app: AppWatcher already handles that activation. A
    // focus event from the app being left must not re-assert its layout / tear
    // down the new app's controller.
    func testSwitchAwaySuppressed() {
        XCTAssertFalse(decide(force: 5, activation: 0.05, wasSelf: false))
    }

    // Clicking the forced app ITSELF to the front (a normal activation of the
    // same app) must NOT be suppressed — its focus event is genuine.
    func testSelfActivationNotSuppressed() {
        XCTAssertTrue(decide(force: 5, activation: 0.05, wasSelf: true))
    }

    // Once the activation guard window has elapsed, a later summon acts again.
    func testActivationGuardExpires() {
        XCTAssertTrue(decide(force: 5, activation: 0.5, wasSelf: false))
    }

    // Burst suppression takes precedence even right after a self-activation.
    func testBurstWinsOverSelfActivation() {
        XCTAssertFalse(decide(force: 0.01, activation: 0.01, wasSelf: true))
    }

    // Boundary: the windows are strict (<), so a value exactly AT the window is
    // NOT suppressed — guards against an off-by-a-hair regression at the edge.
    func testBurstBoundaryIsExclusive() {
        XCTAssertFalse(decide(force: 0.059, activation: 5, wasSelf: false))  // just inside → skip
        XCTAssertTrue(decide(force: 0.06, activation: 5, wasSelf: false))    // exactly at → act
    }

    func testActivationGuardBoundaryIsExclusive() {
        XCTAssertFalse(decide(force: 5, activation: 0.199, wasSelf: false))  // just inside → skip
        XCTAssertTrue(decide(force: 5, activation: 0.20, wasSelf: false))    // exactly at → act
    }
}
