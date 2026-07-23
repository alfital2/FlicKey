import XCTest
@testable import FlicKey

// The welcome tour gate: fresh installs only, once.
final class WelcomeTourTests: XCTestCase {
    private let window = WelcomeTour.freshInstallWindow

    func testFreshInstallShows() {
        XCTAssertTrue(WelcomeTour.shouldShow(firstRun: 1000, now: 1000, seen: false))
        XCTAssertTrue(WelcomeTour.shouldShow(firstRun: 1000, now: 1000 + window - 1, seen: false))
    }

    func testExistingUserNeverSees() {
        XCTAssertFalse(WelcomeTour.shouldShow(firstRun: 1000, now: 1000 + window + 1, seen: false))
    }

    func testSeenNeverRepeats() {
        XCTAssertFalse(WelcomeTour.shouldShow(firstRun: 1000, now: 1000, seen: true))
    }
}
