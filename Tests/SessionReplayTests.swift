import XCTest

// Record-and-replay tests: feed a recorded sequence of real events (the actual
// data an app emitted, in order) through the SHARED decision core and assert the
// resulting memory + applied layouts. This validates the parser and the core
// together against real-world sequences — including the ones that broke naive
// assumptions (tenant-tag flap, multi-word "(External unfamiliar)", switching
// into a non-conversation view) — without clicking through the live app.
//
// Limitation (by design): a fixture is a frozen snapshot of how the app behaved
// when captured. It catches US breaking the logic; it cannot catch the APP
// changing its title format later — only re-capturing does that.
final class SessionReplayTests: XCTestCase {

    enum Event {
        case title(String)        // Teams emitted this window title
        case domain(String?)      // browser navigated here (nil = URL unreadable)
        case inputChange(String)  // user switched layout to this source ID
    }

    private var memory: [String: String]!
    private var applied: [String]!
    private var live: String?

    override func setUp() {
        super.setUp()
        memory = [:]; applied = []; live = nil
    }

    private func makeCore(namespace: String) -> ConversationMemoryCore {
        ConversationMemoryCore(
            namespace: namespace,
            lookup: { [unowned self] _, key in self.memory[key] },
            store: { [unowned self] source, _, key in self.memory[key] = source },
            applySource: { [unowned self] source in self.applied.append(source) },
            currentSource: { [unowned self] in self.live })
    }

    private func replayTeams(_ events: [Event]) {
        let core = makeCore(namespace: "teams")
        for e in events {
            switch e {
            case .inputChange(let s): live = s; core.inputChanged()
            case .title(let t): core.enter(key: TeamsConversationProvider.conversationKey(fromWindowTitle: t))
            case .domain: break
            }
        }
    }

    private func replayBrowser(_ events: [Event]) {
        let core = makeCore(namespace: "site")
        for e in events {
            switch e {
            case .inputChange(let s): live = s; core.inputChanged()
            // nil domain = transient URL-read failure → keep the prior site
            // (don't enter nil), matching TabMemory's behavior.
            case .domain(let d): if let d { core.enter(key: d) }
            case .title: break
            }
        }
    }

    // MARK: - Real captured Teams session

    func testRealTeamsSession_flapAndNonConversationViewsDoNotCorruptMemory() {
        replayTeams([
            .title("Chat | noa nir (External unfamiliar) | Microsoft Teams"),
            .inputChange("Hebrew-PC"),                                    // learn Hebrew for noa nir
            .title("Chat | noa nir | Microsoft Teams"),                   // tenant-tag flap — SAME convo
            .title("Chat | הצוות המנצח (External) | Microsoft Teams"),
            .inputChange("ABC"),                                          // learn English for הצוות המנצח
            .title("Teams and Channels | (External) | Microsoft Teams"),  // NOT a conversation
            .inputChange("Hebrew-PC"),                                    // must not be saved anywhere
            .title("Chat | noa nir | Microsoft Teams"),                   // return to noa nir
        ])

        XCTAssertEqual(memory, ["noa nir": "Hebrew-PC", "הצוות המנצח": "ABC"],
                       "flap collapses to one key; non-conversation views add no keys")
        XCTAssertEqual(applied, ["Hebrew-PC"],
                       "remembered layout reapplied only on returning to noa nir")
    }

    // MARK: - Browser session (same shared core, keyed by domain)

    func testBrowserSession_perSiteRecallAndUnreadableUrlKeepsPriorSite() {
        replayBrowser([
            .domain("ynet.co.il"),
            .inputChange("Hebrew-PC"),   // learn Hebrew for ynet
            .domain("google.com"),
            .inputChange("ABC"),         // learn English for google
            .domain(nil),                // transient URL-read failure → stay on google
            .inputChange("Dvorak"),      // saved under google (still current)
            .domain("ynet.co.il"),       // back to ynet
        ])

        XCTAssertEqual(memory["ynet.co.il"], "Hebrew-PC")
        XCTAssertEqual(memory["google.com"], "Dvorak",
                       "unreadable URL kept google current, so this change saved there")
        XCTAssertEqual(applied, ["Hebrew-PC"],
                       "Hebrew reapplied on returning to a known site (ynet)")
    }

    // MARK: - Switch-then-set (the common flow the old grace window broke)

    // The reported "Teams never remembers" bug: the user clicks a chat and sets
    // its language right away. A genuine change immediately after switching must
    // be saved for the NEW chat — no waiting period.
    //
    // Tradeoff (accepted): the rare inverse — changing layout and INSTANTLY
    // switching chats, so the late notification lands under the new chat — would
    // save that change for the new chat. It's rare and self-correcting, and not
    // having a blunt time window is what makes the common flow work.
    func testTeamsSwitchThenSet_savesForTheNewChat() {
        let core = makeCore(namespace: "teams")

        core.enter(key: TeamsConversationProvider.conversationKey(
            fromWindowTitle: "Chat | noa nir | Microsoft Teams"))
        live = "Hebrew-PC"; core.inputChanged()        // learned for noa nir
        XCTAssertEqual(memory["noa nir"], "Hebrew-PC")

        // Switch to הצוות המנצח and set English right away → saved for הצוות המנצח.
        core.enter(key: TeamsConversationProvider.conversationKey(
            fromWindowTitle: "Chat | הצוות המנצח (External) | Microsoft Teams"))
        live = "ABC"; core.inputChanged()
        XCTAssertEqual(memory["הצוות המנצח"], "ABC", "a change right after switching saves for the new chat")
        XCTAssertEqual(memory["noa nir"], "Hebrew-PC", "noa nir untouched")
    }

    // Returning to a known chat re-applies its language, and that re-apply's echo
    // is NOT mistaken for a user change (so the memory isn't overwritten).
    func testTeamsReturn_reappliesWithoutClobbering() {
        memory["noa nir"] = "Hebrew-PC"
        let core = makeCore(namespace: "teams")
        core.enter(key: TeamsConversationProvider.conversationKey(
            fromWindowTitle: "Chat | noa nir | Microsoft Teams"))   // applies Hebrew-PC
        live = "Hebrew-PC"; core.inputChanged()                     // the apply echo
        XCTAssertEqual(applied, ["Hebrew-PC"])
        XCTAssertEqual(memory["noa nir"], "Hebrew-PC", "echo must not rewrite memory")
    }
}
