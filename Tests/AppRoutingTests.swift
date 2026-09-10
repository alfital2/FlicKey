import XCTest

// Unit tests for the app-activation routing decision (QA areas B/C/D/J).
final class AppRoutingTests: XCTestCase {

    private func decide(_ rule: InputRule?, conversation: Bool) -> AppRouting.Decision {
        AppRouting.decide(rule: rule, isConversationApp: conversation)
    }

    // Forced source

    func testForcedSourceForNormalApp() {
        XCTAssertEqual(decide(.source("He"), conversation: false), .force("He"))
    }

    func testForcedSourceWinsOverConversation() {
        // QA J3 / D5: forcing a language on a conversation app overrides per-chat.
        XCTAssertEqual(decide(.source("En"), conversation: true), .force("En"))
    }

    func testForcedSourceWinsOverBrowserAuto() {
        // A browser whose rule was overridden to a fixed source (QA C6).
        XCTAssertEqual(decide(.source("En"), conversation: false), .force("En"))
    }

    // Conversation app (no forced override)

    func testConversationAppRoutesToConversation() {
        XCTAssertEqual(decide(nil, conversation: true), .conversation)
        XCTAssertEqual(decide(.auto, conversation: true), .conversation)
    }

    // Browser

    func testBrowserAutoRoutesToBrowser() {
        XCTAssertEqual(decide(.auto, conversation: false), .browser)
    }

    // No rule

    func testNoRuleLeavesAsIs() {
        XCTAssertEqual(decide(nil, conversation: false), .leaveAsIs)
    }

    func testUndefinedImportedAppLeavesAsIs() {
        XCTAssertEqual(decide(.undefined, conversation: false), .leaveAsIs)
    }
}
