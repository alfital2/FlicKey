import XCTest

final class AutoSwitchMonitorRecoveryTests: XCTestCase {
    func testRetriesQuicklyThenSettlesAtTenSeconds() {
        var schedule = AutoSwitchMonitorRecoverySchedule()
        let delays = (0..<8).map { _ in schedule.takeNextDelay() }

        XCTAssertEqual(delays, [0.25, 0.5, 1, 2, 5, 10, 10, 10])
        XCTAssertEqual(schedule.attemptsIssued, 8)
    }

    func testRecoveryResetsBackoff() {
        var schedule = AutoSwitchMonitorRecoverySchedule()
        _ = schedule.takeNextDelay()
        _ = schedule.takeNextDelay()
        schedule.reset()

        XCTAssertEqual(schedule.attemptsIssued, 0)
        XCTAssertEqual(schedule.takeNextDelay(), 0.25)
    }
}
