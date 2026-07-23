import XCTest

// Parser tests for the Teams window-title → conversation-key mapping.
// The title FORMATS are the real ones Teams produces; the names/emails/orgs are
// all FABRICATED (no real user data). Covers both the classic
// "Chat | <name> | Microsoft Teams" form and the enterprise form that appends
// "| <org> | <email>" before "| Microsoft Teams".
final class TeamsConversationProviderTests: XCTestCase {

    private func key(_ title: String) -> String? {
        TeamsConversationProvider.conversationKey(fromWindowTitle: title)
    }

    // MARK: - Real conversation titles → a stable key

    func testNamedGroupChat() {
        // Tenant tag stripped → stable key is the name alone.
        XCTAssertEqual(
            key("Chat | The Test Crew (External) | Microsoft Teams"),
            "The Test Crew")
    }

    func testSelfChat() {
        XCTAssertEqual(
            key("Chat | Sam Rivera (You) | Microsoft Teams"),
            "Sam Rivera")
    }

    func testUnnamedTwoPersonChat() {
        XCTAssertEqual(
            key("Chat | guest@example.test and Sam Rivera (External) | Microsoft Teams"),
            "guest@example.test and Sam Rivera")
    }

    // Unicode / RTL coverage (fabricated Hebrew name).
    func testUnicodeName() {
        XCTAssertEqual(
            key("Chat | קבוצת בדיקה (External) | Microsoft Teams"),
            "קבוצת בדיקה")
    }

    // Regression: Teams retitles in two stages, flapping the tenant tag on/off
    // for the SAME conversation. Both forms must yield the SAME stable key, or
    // a conversation's memory splits in two. (Found via live testing.)
    func testTenantTagFlapYieldsSameStableKey() {
        let tagged = key("Chat | Jordan Lee (External) | Microsoft Teams")
        let bare   = key("Chat | Jordan Lee | Microsoft Teams")
        XCTAssertEqual(tagged, "Jordan Lee")
        XCTAssertEqual(tagged, bare)
    }

    func testInternalContactWithNoTag() {
        XCTAssertEqual(key("Chat | John Smith | Microsoft Teams"), "John Smith")
    }

    func testNameLegitimatelyEndingInParenIsKept() {
        // Only relationship tags are stripped; an unrelated parenthetical stays
        // (so distinct chats like "Budget (Q3)"/"Budget (Q4)" don't collide).
        XCTAssertEqual(key("Chat | Budget (Q3) | Microsoft Teams"), "Budget (Q3)")
    }

    // Live capture showed a multi-word tenant tag "(External unfamiliar)" — not
    // just "(External)". All such qualifier variants for the same person must
    // collapse to one stable key, or memory fragments as the qualifier changes.
    func testExternalQualifierVariantsCollapseToOneKey() {
        XCTAssertEqual(key("Chat | Pat Kim | Microsoft Teams"), "Pat Kim")
        XCTAssertEqual(key("Chat | Pat Kim (External) | Microsoft Teams"), "Pat Kim")
        XCTAssertEqual(key("Chat | Pat Kim (External unfamiliar) | Microsoft Teams"), "Pat Kim")
    }

    func testGuestAndInternalQualifiersStripped() {
        XCTAssertEqual(key("Chat | Dana (Guest) | Microsoft Teams"), "Dana")
        XCTAssertEqual(key("Chat | Dana (Internal) | Microsoft Teams"), "Dana")
    }

    // MARK: - Enterprise format: Teams appends "| <org> | <email>" before the
    // suffix. The greedy middle keeps them; they're constant so the key stays
    // stable, and per-chat memory works. (Names/org/email fabricated.)

    func testEnterpriseChatKeepsConstantTrailingSegments() {
        XCTAssertEqual(
            key("Chat | Alice Doe | ACME Corp | alice@acme.test | Microsoft Teams"),
            "Alice Doe | ACME Corp | alice@acme.test")
    }

    func testEnterpriseGroupChatWithSeparatorsInName() {
        XCTAssertEqual(
            key("Chat | Roadmap Sync | Q3 Planning | ACME Corp | alice@acme.test | Microsoft Teams"),
            "Roadmap Sync | Q3 Planning | ACME Corp | alice@acme.test")
    }

    // The module label is UNTRUSTED — Teams flaps it between "Chat" and
    // "Calendar" for the SAME open chat. Both must yield the SAME key, or the
    // flap fragments memory (this was the intermittency).
    func testModuleLabelIsIgnoredSameKeyForChatAndCalendar() {
        let chat     = key("Chat | Alice Doe | ACME Corp | alice@acme.test | Microsoft Teams")
        let calendar = key("Calendar | Alice Doe | ACME Corp | alice@acme.test | Microsoft Teams")
        XCTAssertEqual(chat, "Alice Doe | ACME Corp | alice@acme.test")
        XCTAssertEqual(chat, calendar)
    }

    // MARK: - Non-conversation contexts → nil

    func testChannelListIsNotAConversation() {
        XCTAssertNil(key("Teams and Channels | (External) | Microsoft Teams"))
    }

    func testAssignmentsTabIsNotAConversation() {
        XCTAssertNil(key("Assignments | (External) | Microsoft Teams"))
    }

    func testBareChatListIsNotAConversation() {
        // Chat list with nothing open: only two segments, no middle name.
        XCTAssertNil(key("Chat | Microsoft Teams"))
    }

    func testChatSectionWithOnlyTenantTagIsNotAConversation() {
        // Defensive: a "Chat" section whose middle is just a bare tenant tag
        // has no real name → no key.
        XCTAssertNil(key("Chat | (External) | Microsoft Teams"))
    }

    func testNonTeamsWindowIsNil() {
        XCTAssertNil(key("Some Other App Window"))
        XCTAssertNil(key("Chat | Foo | Some Other App"))
    }

    func testEmptyTitleIsNil() {
        XCTAssertNil(key(""))
    }

    // MARK: - Stability / robustness

    func testUnreadBadgeIsStrippedSoKeyDoesNotFragment() {
        // The same conversation with an unread badge must yield the same key
        // as without it — otherwise memory splits across "(3)"/"(5)".
        let withoutBadge = key("Chat | The Test Crew (External) | Microsoft Teams")
        XCTAssertEqual(key("(3) Chat | The Test Crew (External) | Microsoft Teams"), withoutBadge)
        XCTAssertEqual(key("(12) Chat | The Test Crew (External) | Microsoft Teams"), withoutBadge)
    }

    func testNameContainingSeparatorSurvives() {
        // Greedy middle: a conversation name with " | " in it is kept whole
        // (tenant tag still stripped).
        XCTAssertEqual(
            key("Chat | A | B Project (External) | Microsoft Teams"),
            "A | B Project")
    }

    func testLeadingAndTrailingWhitespaceTolerated() {
        XCTAssertEqual(
            key("  Chat | The Test Crew (External) | Microsoft Teams  "),
            "The Test Crew")
    }

    func testProviderHandlesTeamsBundleIDs() {
        let p = TeamsConversationProvider()
        XCTAssertTrue(p.handles(bundleID: "com.microsoft.teams2"))
        XCTAssertTrue(p.handles(bundleID: "com.microsoft.teams"))
        XCTAssertFalse(p.handles(bundleID: "com.apple.Safari"))
        XCTAssertEqual(p.namespace, "teams")
    }

    // Wiring guard: if the Teams provider is ever dropped from the registry, the
    // feature silently dies while every other test stays green. Assert the
    // registry actually resolves Teams (and not arbitrary apps).
    func testRegistryResolvesTeams() {
        XCTAssertNotNil(ConversationProviderRegistry.provider(forBundleID: "com.microsoft.teams2"))
        XCTAssertNotNil(ConversationProviderRegistry.provider(forBundleID: "com.microsoft.teams"))
        XCTAssertEqual(ConversationProviderRegistry.provider(forBundleID: "com.microsoft.teams2")?.namespace, "teams")
        XCTAssertNil(ConversationProviderRegistry.provider(forBundleID: "com.apple.Safari"))
        XCTAssertNil(ConversationProviderRegistry.provider(forBundleID: nil))
    }

    // The provider exposes the metadata the per-app settings list needs to show
    // a conversation app (e.g. Teams) as a managed row.
    func testProviderExposesListMetadata() {
        let p = TeamsConversationProvider()
        XCTAssertEqual(p.displayName, "Microsoft Teams")
        XCTAssertTrue(p.bundleIDs.contains("com.microsoft.teams2"))
        XCTAssertEqual(p.bundleIDs.first, "com.microsoft.teams2")  // installed one first
    }
}
