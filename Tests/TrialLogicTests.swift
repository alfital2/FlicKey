import XCTest

final class TrialLogicTests: XCTestCase {
    private let day = 24 * 60 * 60

    func testActiveDuringTrial() {
        let d = TrialLogic.decide(state: TrialLogic.start(now: 0), now: 3 * day, isLicensed: false)
        XCTAssertTrue(d.trialActive)
        XCTAssertFalse(d.shouldNag)
        XCTAssertEqual(d.daysUsed, 3)
    }

    func testNagsOnFirstExpiredLaunch() {
        let d = TrialLogic.decide(state: TrialLogic.start(now: 0), now: 8 * day, isLicensed: false)
        XCTAssertFalse(d.trialActive)
        XCTAssertTrue(d.shouldNag)
        XCTAssertEqual(d.newState.lastNag, 8 * day)
    }

    func testNagThrottledToInterval() {
        var s = TrialLogic.start(now: 0); s.lastNag = 8 * day
        XCTAssertFalse(TrialLogic.decide(state: s, now: 9 * day, isLicensed: false).shouldNag)  // 1d < 3d
        XCTAssertTrue(TrialLogic.decide(state: s, now: 11 * day, isLicensed: false).shouldNag)  // 3d
    }

    func testLicensedNeverNags() {
        let d = TrialLogic.decide(state: TrialLogic.start(now: 0), now: 100 * day, isLicensed: true)
        XCTAssertFalse(d.shouldNag)
    }

    func testClockRollbackDoesNotShrinkOrReactivate() {
        let s = TrialLogic.decide(state: TrialLogic.start(now: 0), now: 10 * day, isLicensed: false).newState
        XCTAssertEqual(s.maxElapsed, 10 * day)
        let rolled = TrialLogic.decide(state: s, now: 1 * day, isLicensed: false)  // clock set back
        XCTAssertEqual(rolled.newState.maxElapsed, 10 * day, "elapsed must ratchet, not shrink")
        XCTAssertFalse(rolled.trialActive, "rolling the clock back can't revive the trial")
    }
}
