import XCTest
@testable import FlicKey

// The non-licensed "helped you N times" nudge fires once per 1000-switch
// milestone: only when the total reaches a higher multiple than last shown.
final class StatsNagTests: XCTestCase {

    func testNoNudgeBeforeFirstThousand() {
        XCTAssertNil(StatsNag.milestone(total: 0, lastNagged: 0))
        XCTAssertNil(StatsNag.milestone(total: 999, lastNagged: 0))
    }

    func testFiresAtEachThousandOnce() {
        XCTAssertEqual(StatsNag.milestone(total: 1000, lastNagged: 0), 1000)
        XCTAssertEqual(StatsNag.milestone(total: 1450, lastNagged: 0), 1000)   // floored
        XCTAssertNil(StatsNag.milestone(total: 1450, lastNagged: 1000))         // already shown 1000
        XCTAssertEqual(StatsNag.milestone(total: 2000, lastNagged: 1000), 2000)
        XCTAssertNil(StatsNag.milestone(total: 2001, lastNagged: 2000))
    }

    func testJumpingSeveralThousandsFiresAtCurrentFloor() {
        // A user who crossed many at once still only gets one nudge, at the floor.
        XCTAssertEqual(StatsNag.milestone(total: 5300, lastNagged: 0), 5000)
    }
}
