import XCTest

final class DiagnosticEventTests: XCTestCase {

    private func roundTrip(_ event: DiagnosticEvent) throws -> DiagnosticEvent {
        let data = try JSONEncoder().encode(event)
        return try JSONDecoder().decode(DiagnosticEvent.self, from: data)
    }

    func testCodableRoundTripForEveryCase() throws {
        let cases: [DiagnosticEvent] = [
            .appActivated(bundleID: "com.mitchellh.ghostty"),
            .routingDecision(bundleID: "com.microsoft.teams2", decision: .conversation),
            .layoutSwitch(expected: "com.apple.keylayout.Hebrew-PC", applied: "com.apple.keylayout.ABC"),
            .layoutSwitch(expected: nil, applied: "com.apple.keylayout.US"),
            .conversationKeyResolved(namespace: "teams", keyHash: "a3f9c1", hadMemory: true),
            .siteResolved(domainHash: "b21e07", hadMemory: false),
            .memoryApplied(scope: "teams", keyHash: "a3f9c1", source: "com.apple.keylayout.Hebrew-PC"),
            .memorySaved(scope: "site", keyHash: "b21e07", source: "com.apple.keylayout.ABC"),
            .conversationUnreadable(namespace: "teams"),
            .panelEvent(kind: .dismissed),
            .autoSwitchStreakOpened(signal: .tell, script: "hebrew", wordLength: 3),
            .autoSwitchFired(target: "com.apple.keylayout.Hebrew-PC", signal: .misspelled),
            .autoSwitchUndone(wordsRejected: 2),
            .autoSwitchRejected(reason: .noValidSwap, script: "latin", wordLength: 5),
            .autoSwitchRunBroken(by: .key),
            .autoSwitchMonitorUnavailable(reason: .accessibilityDenied),
            .autoSwitchMonitorRecovered(attempts: 3),
            .autoSwitchRewriteAnomaly(kind: .orphanFragment),
            .autoSwitchRewriteAnomaly(kind: .tailMutated),
            .autoSwitchSpanFallback(reason: .axUnreadable),
            .autoSwitchSpanFallback(reason: .spanOutOfRange),
        ]
        for event in cases {
            XCTAssertEqual(try roundTrip(event), event, "round-trip failed for \(event.line)")
        }
    }

    // The line rendering is built only from categorical fields, so it reflects the
    // input-source IDs and enum tokens, never anything resembling typed content.
    func testLineRendering() {
        XCTAssertEqual(
            DiagnosticEvent.routingDecision(bundleID: "com.x", decision: .force).line,
            "routing com.x → force")
        XCTAssertEqual(
            DiagnosticEvent.conversationKeyResolved(namespace: "teams", keyHash: "a3f9c1", hadMemory: false).line,
            "conversation[teams] → a3f9c1 (memory: no)")
        XCTAssertEqual(
            DiagnosticEvent.siteResolved(domainHash: "b21e07", hadMemory: true).line,
            "site → b21e07 (memory: yes)")
        XCTAssertEqual(
            DiagnosticEvent.memoryApplied(scope: "site", keyHash: "b21e07", source: "com.apple.keylayout.ABC").line,
            "memory applied: site b21e07 → com.apple.keylayout.ABC")
        XCTAssertEqual(
            DiagnosticEvent.memorySaved(scope: "teams", keyHash: "a3f9c1", source: "com.apple.keylayout.Hebrew-PC").line,
            "memory saved: teams a3f9c1 → com.apple.keylayout.Hebrew-PC")
        XCTAssertEqual(
            DiagnosticEvent.conversationUnreadable(namespace: "teams").line,
            "conversation[teams] unreadable (AX not ready)")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchFired(target: "com.apple.keylayout.Hebrew-PC", signal: .tell).line,
            "auto-switch fired (tell) → com.apple.keylayout.Hebrew-PC")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchUndone(wordsRejected: 2).line,
            "auto-switch undone (2 words rejected)")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchRejected(reason: .learnedException, script: "hebrew", wordLength: 4).line,
            "auto-switch rejected: learnedException (hebrew, 4 chars)")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchRunBroken(by: .key).line,
            "auto-switch run broken by key")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchMonitorUnavailable(reason: .monitorCreationFailed).line,
            "auto-switch monitor unavailable: monitorCreationFailed")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchMonitorRecovered(attempts: 3).line,
            "auto-switch monitor recovered after 3 retries")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchRewriteAnomaly(kind: .orphanFragment).line,
            "auto-switch rewrite anomaly: orphanFragment")
        XCTAssertEqual(
            DiagnosticEvent.autoSwitchSpanFallback(reason: .axUnreadable).line,
            "auto-switch span fallback: axUnreadable")
    }
}
