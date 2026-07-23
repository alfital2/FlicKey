import XCTest

// Parser tests for the Slack window-title → conversation-key mapping.
// Title FORMATS are the real ones Slack produces; names/workspaces are fabricated.
final class SlackConversationProviderTests: XCTestCase {

    private func key(_ title: String) -> String? {
        SlackConversationProvider.conversationKey(fromWindowTitle: title)
    }

    func testDirectMessageKeepsTypeSuffix() {
        // "(DM)" stays: it's constant and disambiguates a DM from a channel of
        // the same name. The workspace is dropped.
        XCTAssertEqual(
            key("Alex Rivera (DM) - Acme Workspace - Slack"),
            "Alex Rivera (DM)")
    }

    func testChannel() {
        XCTAssertEqual(
            key("#general - Acme Workspace - Slack"),
            "#general")
    }

    func testConversationNameContainingSeparatorSurvives() {
        // Only the trailing workspace segment is dropped; a name with " - " in it
        // is kept whole.
        XCTAssertEqual(
            key("Roadmap - 2026 (DM) - Acme Workspace - Slack"),
            "Roadmap - 2026 (DM)")
    }

    func testUnreadBadgeStrippedSoKeyDoesNotFragment() {
        let plain = key("Alex Rivera (DM) - Acme Workspace - Slack")
        XCTAssertEqual(key("(3) Alex Rivera (DM) - Acme Workspace - Slack"), plain)
        XCTAssertEqual(key("(12) Alex Rivera (DM) - Acme Workspace - Slack"), plain)
    }

    func testWorkspaceHomeIsNotAConversation() {
        XCTAssertNil(key("Acme Workspace - Slack"))
    }

    func testPipeSlackSuffixAlsoAccepted() {
        XCTAssertEqual(key("Alex Rivera (DM) - Acme Workspace | Slack"), "Alex Rivera (DM)")
    }

    func testNonSlackWindowIsNil() {
        XCTAssertNil(key("Some Other App Window"))
        XCTAssertNil(key(""))
    }

    func testProviderMetadataAndRegistry() {
        let p = SlackConversationProvider()
        XCTAssertEqual(p.namespace, "slack")
        XCTAssertEqual(p.displayName, "Slack")
        XCTAssertTrue(p.handles(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertNotNil(ConversationProviderRegistry.provider(forBundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertEqual(ConversationProviderRegistry.provider(forBundleID: "com.tinyspeck.slackmacgap")?.namespace, "slack")
    }
}
