import XCTest

final class DiagnosticConsentTests: XCTestCase {

    private let keys = ["diagRecordEnabled", "diagInstallID"]
    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    func testDefaultsAreOff() {
        XCTAssertFalse(DiagnosticConsent.isRecordingEnabled)
    }

    func testTogglePersists() {
        DiagnosticConsent.isRecordingEnabled = true
        XCTAssertTrue(DiagnosticConsent.isRecordingEnabled)
        DiagnosticConsent.isRecordingEnabled = false
        XCTAssertFalse(DiagnosticConsent.isRecordingEnabled)
    }

    func testInstallIDIsCreatedOnceAndStable() {
        let first = DiagnosticConsent.installID
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, DiagnosticConsent.installID, "install ID must be stable")
        XCTAssertNotNil(UUID(uuidString: first), "install ID is a random UUID, not a device ID")
    }
}
