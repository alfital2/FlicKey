import XCTest

final class AccessibilityTrustMonitorTests: XCTestCase {
    func testInitialCheckProducesAState() {
        var state = AccessibilityTrustStateTracker()
        XCTAssertEqual(state.accept(false), false)
        XCTAssertEqual(state.current, false)
    }

    func testRepeatedChecksDoNotProduceTransitions() {
        var state = AccessibilityTrustStateTracker()
        XCTAssertEqual(state.accept(true), true)
        XCTAssertNil(state.accept(true))
        XCTAssertNil(state.accept(true))
    }

    func testGrantAndRevocationProduceTransitions() {
        var state = AccessibilityTrustStateTracker()
        _ = state.accept(false)
        XCTAssertEqual(state.accept(true), true)
        XCTAssertEqual(state.accept(false), false)
    }
}
