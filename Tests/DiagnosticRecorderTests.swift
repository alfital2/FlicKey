import XCTest

final class DiagnosticRecorderTests: XCTestCase {

    // A controllable clock so age-trimming is deterministic.
    private final class Clock {
        var t = Date(timeIntervalSince1970: 1_000_000)
        func now() -> Date { t }
        func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
    }

    func testNoOpWhenDisabled() {
        let rec = DiagnosticRecorder(isEnabled: { false }, appVersion: "t")
        rec.log(.appActivated(bundleID: "com.x"))
        XCTAssertTrue(rec.snapshot().isEmpty, "nothing recorded while recording is off")
    }

    func testRecordsWhenEnabled() {
        let rec = DiagnosticRecorder(isEnabled: { true }, appVersion: "t")
        rec.log(.appActivated(bundleID: "com.x"))
        XCTAssertEqual(rec.snapshot().count, 1)
        XCTAssertEqual(rec.snapshot().first?.event, .appActivated(bundleID: "com.x"))
    }

    func testEvictsOldestBeyondCapacity() {
        let rec = DiagnosticRecorder(capacity: 3, isEnabled: { true }, appVersion: "t")
        for i in 0..<5 { rec.log(.routingDecision(bundleID: "\(i)", decision: .force)) }
        let ids = rec.snapshot().compactMap { entry -> String? in
            if case .routingDecision(let b, _) = entry.event { return b }; return nil
        }
        XCTAssertEqual(ids, ["2", "3", "4"], "keeps only the newest `capacity` events")
    }

    func testSnapshotDropsEntriesOlderThanMaxAge() {
        let clock = Clock()
        let rec = DiagnosticRecorder(capacity: 100, maxAge: 3600,
                                     isEnabled: { true }, now: clock.now, appVersion: "t")
        rec.log(.panelEvent(kind: .shown))     // t0
        clock.advance(4000)                     // > 1h later
        rec.log(.panelEvent(kind: .dismissed)) // t1
        let snap = rec.snapshot()
        XCTAssertEqual(snap.count, 1, "the >1h-old entry is trimmed at read time")
        XCTAssertEqual(snap.first?.event, .panelEvent(kind: .dismissed))
    }

    func testClearForgetsEverything() {
        let rec = DiagnosticRecorder(isEnabled: { true }, appVersion: "t")
        rec.log(.routingDecision(bundleID: "com.x", decision: .force))
        rec.clear()
        XCTAssertTrue(rec.snapshot().isEmpty)
    }
}
