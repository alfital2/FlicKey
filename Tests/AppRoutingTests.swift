import XCTest

// Unit tests for the app-activation routing decision (QA areas B/C/D/J).
final class AppRoutingTests: XCTestCase {

    private func decide(_ rule: InputRule?, kind: AppKind?) -> AppRouting.Decision {
        AppRouting.decide(rule: rule, kind: kind)
    }

    // Forced source

    func testForcedSourceForNormalApp() {
        XCTAssertEqual(decide(.source("He"), kind: .normal), .force("He"))
    }

    func testForcedSourceWinsOverConversation() {
        // QA J3 / D5: forcing a language on a conversation app overrides per-chat.
        XCTAssertEqual(decide(.source("En"), kind: .conversation), .force("En"))
    }

    func testForcedSourceWinsOverBrowserAuto() {
        // A browser whose rule was overridden to a fixed source (QA C6).
        XCTAssertEqual(decide(.source("En"), kind: .browser), .force("En"))
    }

    // Conversation app (no forced override)

    func testConversationAppRoutesToConversation() {
        XCTAssertEqual(decide(.auto, kind: .conversation), .conversation)
    }

    // Browser

    func testBrowserAutoRoutesToBrowser() {
        XCTAssertEqual(decide(.auto, kind: .browser), .browser)
    }

    func testNormalMemoryModesRouteAppWide() {
        XCTAssertEqual(decide(.auto, kind: .normal), .rememberApp)
    }

    // No rule

    func testNoRuleLeavesAsIs() {
        XCTAssertEqual(decide(nil, kind: .normal), .leaveAsIs)
    }

    func testUndefinedImportedAppLeavesAsIs() {
        XCTAssertEqual(decide(.undefined, kind: .normal), .leaveAsIs)
    }
}
