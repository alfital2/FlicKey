import XCTest

// Deterministic tests for the per-conversation decision logic, with all I/O
// (memory store, layout apply, current-source read) replaced by spies.
final class ConversationMemoryCoreTests: XCTestCase {

    private var memory: [String: String]!       // conversationKey -> sourceID
    private var applied: [String]!              // sources applied (switchTo)
    private var saved: [String]!                // "key=source" writes
    private var liveSource: String?             // what currentSource() returns

    override func setUp() {
        super.setUp()
        memory = [:]; applied = []; saved = []; liveSource = nil
    }

    // `now` is injectable so the echo-window tests can drive time; the default
    // real clock keeps the synchronous tests' calls inside one echo window.
    private func makeCore(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime })
        -> ConversationMemoryCore {
        ConversationMemoryCore(
            namespace: "teams",
            lookup: { [unowned self] _, key in self.memory[key] },
            store: { [unowned self] source, _, key in
                self.memory[key] = source
                self.saved.append("\(key)=\(source)")
            },
            // Applying a source also makes it the live source — so the echoed
            // inputChanged() reports it, exactly as the real system does.
            applySource: { [unowned self] source in self.applied.append(source); self.liveSource = source },
            currentSource: { [unowned self] in self.liveSource },
            now: now)
    }

    // MARK: - enter()

    func testEnterKnownConversationAppliesRememberedSource() {
        memory["Alex"] = "Hebrew"
        let core = makeCore()
        core.enter(key: "Alex")
        XCTAssertEqual(applied, ["Hebrew"])
        XCTAssertEqual(core.currentKey, "Alex")
    }

    func testEnterUnknownConversationDoesNothing() {
        let core = makeCore()
        core.enter(key: "Brand New Chat")
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(core.currentKey, "Brand New Chat")
    }

    func testEnterNilContextAppliesNothing() {
        memory["Alex"] = "Hebrew"
        let core = makeCore()
        core.enter(key: nil)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertNil(core.currentKey)
    }

    func testReEnteringSameKeyIsANoOp() {
        memory["Alex"] = "Hebrew"
        let core = makeCore()
        core.enter(key: "Alex")
        core.enter(key: "Alex")     // duplicate retitle
        XCTAssertEqual(applied, ["Hebrew"], "should apply only once")
    }

    // MARK: - inputChanged()

    func testInputChangeSavesUnderCurrentConversation() {
        let core = makeCore()
        core.enter(key: "Alex")           // unknown → no apply, no pending echo
        liveSource = "English"
        core.inputChanged()
        XCTAssertEqual(memory["Alex"], "English")
        XCTAssertEqual(saved, ["Alex=English"])
    }

    func testInputChangeWithNoActiveConversationDoesNotSave() {
        let core = makeCore()
        liveSource = "English"
        core.inputChanged()
        XCTAssertTrue(saved.isEmpty)
    }

    func testInputChangeInNilContextDoesNotSave() {
        let core = makeCore()
        core.enter(key: nil)
        liveSource = "English"
        core.inputChanged()
        XCTAssertTrue(saved.isEmpty)
    }

    func testLastWriteWins() {
        let core = makeCore()
        core.enter(key: "Alex")
        liveSource = "Hebrew"; core.inputChanged()
        liveSource = "English"; core.inputChanged()
        XCTAssertEqual(memory["Alex"], "English")
    }

    // MARK: - echo handling (apply-echo vs a real change)

    // Entering a known conversation switches the layout, which echoes an
    // inputChanged reporting the source we just applied. That echo must NOT be
    // re-saved as if the user had changed it.
    func testApplyEchoIsIgnored() {
        memory["Alex"] = "Hebrew"
        let core = makeCore()
        core.enter(key: "Alex")     // applies Hebrew (→ liveSource = Hebrew)
        core.inputChanged()         // the echo of that apply
        XCTAssertTrue(saved.isEmpty, "the echo of our own apply must not be re-saved")
    }

    func testStalePreApplyNotificationDoesNotOverwriteDestination() {
        memory["Alex"] = "Hebrew"
        liveSource = "English"
        var clock = 0.0
        let core = ConversationMemoryCore(
            namespace: "teams",
            lookup: { [unowned self] _, key in self.memory[key] },
            store: { [unowned self] source, _, key in
                self.memory[key] = source
                self.saved.append("\(key)=\(source)")
            },
            // Model the real asynchronous switch: it has been requested, but
            // currentSource still reports the old layout for a few milliseconds.
            applySource: { [unowned self] source in self.applied.append(source) },
            currentSource: { [unowned self] in self.liveSource },
            now: { clock })

        core.enter(key: "Alex")
        clock = 0.03
        core.inputChanged() // stale queued English notification
        XCTAssertEqual(memory["Alex"], "Hebrew")
        XCTAssertTrue(saved.isEmpty)

        liveSource = "Hebrew"
        clock = 0.05
        core.inputChanged() // requested source finally becomes observable
        XCTAssertTrue(saved.isEmpty)
    }

    // THE fix for the reported "Teams never remembers" bug: a genuine change the
    // user makes immediately after switching chats is saved — no waiting period.
    func testGenuineChangeRightAfterSwitchIsSaved() {
        memory["Alex"] = "Hebrew"
        let core = makeCore()
        core.enter(key: "Alex")     // applies Hebrew, arms the one-shot echo
        core.inputChanged()         // the echo (Hebrew) — consumed, ignored
        liveSource = "English"      // user immediately switches to English
        core.inputChanged()
        XCTAssertEqual(memory["Alex"], "English", "a real change right after enter must save")
    }

    // Once the applied source has been observed, a genuine change away and back
    // is saved normally.
    func testEchoIsOnlyIgnoredOnce() {
        memory["Alex"] = "Hebrew"
        let core = makeCore()
        core.enter(key: "Alex")                       // applies Hebrew, arms echo
        core.inputChanged()                            // observe applied Hebrew
        liveSource = "English"; core.inputChanged()   // genuine change → saved
        liveSource = "Hebrew";  core.inputChanged()   // user deliberately goes back to Hebrew → saved
        XCTAssertEqual(memory["Alex"], "Hebrew")
        XCTAssertEqual(saved, ["Alex=English", "Alex=Hebrew"])
    }

    // THE Safari per-site corruption fix. Measured: applying a source fires the
    // prompt echo AND extra delayed "settling" duplicates (~330ms later), all
    // reporting the applied source. The shipped one-shot guard let the duplicates
    // through; they must ALL be ignored, not just the first.
    func testDelayedSettlingDuplicatesAreAllIgnored() {
        memory["site"] = "L"
        var clock = 0.0
        let core = makeCore(now: { clock })
        core.enter(key: "site")              // apply L (live = L)
        clock = 0.005; core.inputChanged()   // prompt echo
        clock = 0.330; core.inputChanged()   // delayed settling duplicate #1
        clock = 0.345; core.inputChanged()   // delayed settling duplicate #2
        XCTAssertEqual(saved, [], "the apply echo and all its delayed duplicates must be ignored")
    }

    // A delayed settling echo arriving after the key has advanced (the real
    // flip-flop) must not be saved under the new key.
    func testSettlingEchoAfterKeyAdvanceDoesNotCorrupt() {
        memory["siteA"] = "LA"; memory["siteB"] = "LB"
        var clock = 0.0
        let core = makeCore(now: { clock })
        core.enter(key: "siteA"); clock = 0.005; core.inputChanged()   // apply LA, echo ignored
        clock = 0.05
        core.enter(key: "siteB"); clock = 0.055; core.inputChanged()   // apply LB, echo ignored
        clock = 0.34; core.inputChanged()                              // delayed settling (reports LB)
        XCTAssertEqual(saved, [], "no settling echo saved under the advanced key")
        XCTAssertEqual(memory["siteB"], "LB")
    }

    // Regression for the cross-key lost-save: a genuine change to a layout that
    // was auto-applied for ANOTHER key must still be saved (we track only the
    // last applied source, so it isn't mistaken for that other key's echo).
    func testGenuineChangeToAnotherKeysAppliedSourceIsSaved() {
        memory["siteA"] = "Hebrew"; memory["siteB"] = "English"
        var clock = 0.0
        let core = makeCore(now: { clock })
        core.enter(key: "siteA"); clock = 0.005; core.inputChanged()   // apply Hebrew, echo ignored
        clock = 0.3
        core.enter(key: "siteB"); clock = 0.305; core.inputChanged()   // apply English, echo ignored
        clock = 0.5; liveSource = "Hebrew"; core.inputChanged()        // user picks Hebrew on siteB
        XCTAssertEqual(memory["siteB"], "Hebrew", "a genuine cross-key change must be saved")
    }

    // MARK: - reset() — the handoff invariant

    func testResetPreventsStaleKeyWrite() {
        let core = makeCore()
        core.enter(key: "Alex")
        core.reset()
        liveSource = "English"
        core.inputChanged()
        XCTAssertTrue(saved.isEmpty, "no write under a stale key after reset")
        XCTAssertNil(core.currentKey)
    }

    // MARK: - full round trip

    func testLearnLeaveAndReturnReapplies() {
        let core = makeCore()
        core.enter(key: "Alex")                     // unknown → no apply
        liveSource = "Hebrew"; core.inputChanged()  // learn Hebrew for Alex
        core.enter(key: "Bob")                      // switch away (unknown)
        core.enter(key: "Alex")                     // return → Alex now known
        XCTAssertEqual(applied, ["Hebrew"], "Hebrew reapplied on return to Alex")
    }
}
