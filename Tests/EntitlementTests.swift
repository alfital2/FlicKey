import XCTest

final class EntitlementTests: XCTestCase {

    private let day = 24 * 60 * 60
    private let cutoff = 1_000_000            // arbitrary fixed cutoff for tests
    private func before() -> Int { cutoff - day }   // a first-launch before the cutoff
    private func after() -> Int { cutoff + day }    // a first-launch after the cutoff

    private func state(firstRun: Int, maxElapsed: Int = 0) -> TrialState {
        TrialState(firstRun: firstRun, maxElapsed: maxElapsed, lastNag: 0)
    }

    // MARK: - Licensed overrides everything

    func testLicensedIsAlwaysLicensed() {
        // Even a brand-new, long-expired-looking trial: a key wins.
        let s = state(firstRun: after(), maxElapsed: 999 * day)
        XCTAssertEqual(Entitlement.decide(trial: s, now: after() + 999 * day,
                                          isLicensed: true, cutoff: cutoff), .licensed)
    }

    // MARK: - Grandfathering (installed under the promise)

    func testInstalledBeforeCutoffIsGrandfathered() {
        let s = state(firstRun: before())
        XCTAssertEqual(Entitlement.decide(trial: s, now: before() + day,
                                          isLicensed: false, cutoff: cutoff), .grandfathered)
    }

    func testGrandfatheredForeverEvenAfterYears() {
        // The promise has no expiry: elapsed time is irrelevant before the cutoff.
        let s = state(firstRun: before(), maxElapsed: 900 * day)
        XCTAssertEqual(Entitlement.decide(trial: s, now: before() + 900 * day,
                                          isLicensed: false, cutoff: cutoff), .grandfathered)
    }

    func testCutoffBoundaryIsExclusive() {
        // firstRun exactly at the cutoff is a NEW user (not grandfathered).
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: cutoff), now: cutoff,
                                          isLicensed: false, cutoff: cutoff),
                       .trial(daysLeft: 30))
        // One second before → grandfathered.
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: cutoff - 1), now: cutoff,
                                          isLicensed: false, cutoff: cutoff), .grandfathered)
    }

    // MARK: - Trial (installed after the cutoff)

    func testFreshTrialHas30DaysLeft() {
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: after()), now: after(),
                                          isLicensed: false, cutoff: cutoff),
                       .trial(daysLeft: 30))
    }

    func testTrialCountsDownByWholeDaysRoundedUp() {
        let start = after()
        // 15 full days in → 15 left.
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: start), now: start + 15 * day,
                                          isLicensed: false, cutoff: cutoff),
                       .trial(daysLeft: 15))
        // 29 days and 12 hours in → still inside, rounds up to 1 day left.
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: start),
                                          now: start + 29 * day + day / 2,
                                          isLicensed: false, cutoff: cutoff),
                       .trial(daysLeft: 1))
    }

    func testTrialExpiresAtExactly30Days() {
        let start = after()
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: start), now: start + 30 * day,
                                          isLicensed: false, cutoff: cutoff), .expired)
        XCTAssertEqual(Entitlement.decide(trial: state(firstRun: start), now: start + 30 * day + 1,
                                          isLicensed: false, cutoff: cutoff), .expired)
    }

    // MARK: - Clock-rollback ratchet

    func testRolledBackClockDoesNotReviveAnExpiredTrial() {
        // maxElapsed already recorded 31 days; the clock is now rolled back so
        // now - firstRun looks like 0. The ratchet must keep it expired.
        let s = state(firstRun: after(), maxElapsed: 31 * day)
        XCTAssertEqual(Entitlement.decide(trial: s, now: after(),
                                          isLicensed: false, cutoff: cutoff), .expired)
    }

    // MARK: - coreEnabled

    func testCoreEnabledOnlyOffWhenExpired() {
        XCTAssertTrue(Entitlement.licensed.coreEnabled)
        XCTAssertTrue(Entitlement.grandfathered.coreEnabled)
        XCTAssertTrue(Entitlement.trial(daysLeft: 1).coreEnabled)
        XCTAssertFalse(Entitlement.expired.coreEnabled)
    }

    // MARK: - Shipped default is fail-safe

    func testDefaultCutoffGrandfathersEveryoneUntilSet() {
        // With the shipped far-future default cutoff, a brand-new install is still
        // grandfathered — the gate can never wrongly fire before the date is set.
        let nowish = 1_800_000_000   // ~2027, well before the 2100 default
        let s = state(firstRun: nowish)
        XCTAssertEqual(Entitlement.decide(trial: s, now: nowish, isLicensed: false),
                       .grandfathered)
    }
}
