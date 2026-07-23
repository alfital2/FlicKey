import XCTest

final class ReportComposerTests: XCTestCase {

    private let env = DiagnosticEnvironment(
        appVersion: "0.4.3 (15)",
        osVersion: "macOS 26.0",
        installID: "11111111-2222-3333-4444-555555555555",
        enabledInputSources: ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew-PC"],
        autoSwitchBeta: nil)

    private func entry(_ event: DiagnosticEvent) -> DiagnosticEntry {
        DiagnosticEntry(at: Date(timeIntervalSince1970: 1_000_000), event: event, appVersion: "0.4.3 (15)")
    }

    func testBodyIncludesEnvironment() {
        let report = ReportComposer.compose(entries: [entry(.appActivated(bundleID: "com.x"))],
                                            environment: env)
        XCTAssertTrue(report.body.contains("0.4.3 (15)"))
        XCTAssertTrue(report.body.contains("macOS 26.0"))
        XCTAssertTrue(report.body.contains(env.installID))
        XCTAssertTrue(report.body.contains("com.apple.keylayout.Hebrew-PC"))
    }

    func testSubjectCarriesAppVersion() {
        let report = ReportComposer.compose(entries: [entry(.appActivated(bundleID: "com.x"))],
                                            environment: env)
        XCTAssertTrue(report.subject.contains("0.4.3 (15)"))
    }

    func testUserNoteIsIncludedWhenPresent() {
        let report = ReportComposer.compose(entries: [], environment: env,
                                            note: "typed Hebrew but got English")
        XCTAssertTrue(report.body.contains("typed Hebrew but got English"))
    }

    func testJSONAttachmentIsValidAndCarriesEntries() throws {
        let entries = [entry(.appActivated(bundleID: "com.x")),
                       entry(.routingDecision(bundleID: "com.x", decision: .force))]
        let report = ReportComposer.compose(entries: entries, environment: env)
        let obj = try JSONSerialization.jsonObject(with: report.jsonData) as? [String: Any]
        XCTAssertEqual(obj?["installID"] as? String, env.installID)
        XCTAssertEqual((obj?["entries"] as? [Any])?.count, 2)
    }

    // MARK: - Auto-switch beta context

    private var envWithBeta: DiagnosticEnvironment {
        DiagnosticEnvironment(
            appVersion: "0.4.3 (15)", osVersion: "macOS 26.0",
            installID: "11111111-2222-3333-4444-555555555555",
            enabledInputSources: ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew-PC"],
            autoSwitchBeta: AutoSwitchReportContext(
                functionalDictionaries: ["en", "he"],
                missingDictionaries: ["el"],
                learnedExceptionCount: 3))
    }

    func testAutoSwitchSectionAppearsWhenBetaContextPresent() {
        let report = ReportComposer.compose(entries: [], environment: envWithBeta)
        XCTAssertTrue(report.body.contains("Auto-switch (beta)"))
        XCTAssertTrue(report.body.contains("en, he"))
        XCTAssertTrue(report.body.contains("el"))
        XCTAssertTrue(report.body.contains("3"))
    }

    func testAutoSwitchSectionAbsentWhenBetaOff() {
        let report = ReportComposer.compose(entries: [], environment: env)
        XCTAssertFalse(report.body.contains("Auto-switch (beta)"))
    }

    func testAutoSwitchContextCarriedInJSON() throws {
        let report = ReportComposer.compose(entries: [], environment: envWithBeta)
        let obj = try JSONSerialization.jsonObject(with: report.jsonData) as? [String: Any]
        let beta = obj?["autoSwitchBeta"] as? [String: Any]
        XCTAssertEqual(beta?["learnedExceptionCount"] as? Int, 3)
        XCTAssertEqual(beta?["functionalDictionaries"] as? [String], ["en", "he"])
    }

    // Privacy boundary: a conversation event records only WHETHER memory existed,
    // never the conversation's name. There is no field to hold it, so a name the
    // caller might have (but must not pass) can never reach the output.
    func testConversationEventCarriesNoIdentifyingText() {
        let secretConversationName = "Dana Bloom"
        let report = ReportComposer.compose(
            entries: [entry(.conversationKeyResolved(
                namespace: "teams",
                keyHash: DiagnosticHash.token(secretConversationName, salt: "x"),
                hadMemory: true))],
            environment: env)
        XCTAssertFalse(report.body.contains(secretConversationName),
                       "the conversation name must never appear in a report")
        XCTAssertFalse(String(data: report.jsonData, encoding: .utf8)!.contains(secretConversationName))
        XCTAssertTrue(report.body.contains("memory: yes"))
    }
}
