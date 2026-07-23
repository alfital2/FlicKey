import XCTest

// Unit tests for the pure double-tap-Shift decision logic. No NSEvent needed —
// we drive the state machine with synthetic transitions and timestamps.
final class DoubleTapTests: XCTestCase {

    // One clean Shift tap: down then up, no other key/modifier.
    private func tap(_ m: inout DoubleTapStateMachine, down: TimeInterval, up: TimeInterval) -> Bool {
        m.shiftDown(otherMods: false, at: down)
        return m.shiftUp(otherMods: false, at: up)
    }

    func testTwoQuickTapsFire() {
        var m = DoubleTapStateMachine()
        XCTAssertFalse(tap(&m, down: 0.00, up: 0.05))   // first tap
        XCTAssertTrue(tap(&m, down: 0.10, up: 0.15))    // second within window → fire
    }

    func testSecondTapTooLateDoesNotFire() {
        var m = DoubleTapStateMachine()
        _ = tap(&m, down: 0.0, up: 0.05)
        XCTAssertFalse(tap(&m, down: 1.0, up: 1.05), "gap > window must not fire")
    }

    func testLongHoldIsNotATap() {
        var m = DoubleTapStateMachine()
        _ = tap(&m, down: 0.0, up: 0.05)
        // A long press (> maxTapDuration) isn't a tap, so it can't complete a pair.
        XCTAssertFalse(tap(&m, down: 0.10, up: 0.60))
    }

    func testInterveningKeyCancels() {
        var m = DoubleTapStateMachine()
        _ = tap(&m, down: 0.0, up: 0.05)
        // Hold Shift and type a letter — Shift was a modifier, not a tap.
        m.shiftDown(otherMods: false, at: 0.10)
        m.keyPressed()
        XCTAssertFalse(m.shiftUp(otherMods: false, at: 0.14))
    }

    func testOtherModifierCancels() {
        var m = DoubleTapStateMachine()
        _ = tap(&m, down: 0.0, up: 0.05)
        // Shift released while ⌘ is also held → not a clean tap.
        m.shiftDown(otherMods: false, at: 0.10)
        XCTAssertFalse(m.shiftUp(otherMods: true, at: 0.14))
    }

    func testThreeTapsFireOnceThenRearm() {
        var m = DoubleTapStateMachine()
        XCTAssertFalse(tap(&m, down: 0.0, up: 0.05))
        XCTAssertTrue(tap(&m, down: 0.10, up: 0.15))   // fires
        // After firing, the pair resets: a third lone tap should not re-fire.
        XCTAssertFalse(tap(&m, down: 0.20, up: 0.25))
    }
}
