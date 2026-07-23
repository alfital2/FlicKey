import XCTest

// Uses Safari, which ships on every Mac, so these stay deterministic.
final class AppFinderTests: XCTestCase {

    func testSearchFindsBundledApp() {
        let results = AppFinder.search("safari")
        XCTAssertTrue(results.contains { $0.name.lowercased().contains("safari") })
    }

    func testSearchEmptyQueryReturnsNothing() {
        XCTAssertTrue(AppFinder.search("").isEmpty)
    }

    func testSearchRespectsLimit() {
        XCTAssertLessThanOrEqual(AppFinder.search("a", limit: 3).count, 3)
    }

    func testFindReturnsURL() {
        XCTAssertNotNil(AppFinder.find(named: "Safari"))
    }

    func testInfoExtractsNameAndBundleID() {
        guard let url = AppFinder.find(named: "Safari") else { return XCTFail("Safari not found") }
        let info = AppFinder.info(at: url)
        XCTAssertFalse(info.name.isEmpty)
        XCTAssertEqual(info.bundleID, "com.apple.Safari")
    }
}
