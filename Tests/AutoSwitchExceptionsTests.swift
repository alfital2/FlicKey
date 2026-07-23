import XCTest

final class AutoSwitchExceptionsTests: XCTestCase {

    private let suite = "test.flickey.autoSwitchExceptions"
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: suite)
        store.removePersistentDomain(forName: suite)
    }
    override func tearDown() {
        store.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func make(threshold: Int = 2, cap: Int = 500) -> AutoSwitchExceptions {
        AutoSwitchExceptions(store: store, blockThreshold: threshold, cap: cap)
    }

    func testNotBlockedByDefault() {
        XCTAssertFalse(make().isBlocked("akuo"))
    }

    func testOneRejectionDoesNotBlock() {
        let ex = make()
        ex.recordRejection("akuo")
        XCTAssertFalse(ex.isBlocked("akuo"), "a single undo must not permanently block")
    }

    func testTwoRejectionsBlock() {
        let ex = make()
        ex.recordRejection("akuo")
        ex.recordRejection("akuo")
        XCTAssertTrue(ex.isBlocked("akuo"))
    }

    func testAcceptanceResetsRejectionCount() {
        let ex = make()
        ex.recordRejection("akuo")          // one accidental undo
        ex.recordAcceptance("akuo")         // later accepted → forgiven
        ex.recordRejection("akuo")          // a fresh single rejection
        XCTAssertFalse(ex.isBlocked("akuo"), "acceptance should reset the count")
    }

    func testAcceptanceUnblocksAWordThatReachedTheThreshold() {
        // If somehow accepted while blocked (via manual convert), it un-blocks.
        let ex = make()
        ex.recordRejection("akuo"); ex.recordRejection("akuo")
        XCTAssertTrue(ex.isBlocked("akuo"))
        ex.recordAcceptance("akuo")
        XCTAssertFalse(ex.isBlocked("akuo"))
    }

    func testNormalizesCaseAndWhitespace() {
        let ex = make()
        ex.recordRejection("Akuo"); ex.recordRejection("  akuo ")
        XCTAssertTrue(ex.isBlocked("AKUO"))
    }

    func testEmptyWordIsNeverBlockedOrRecorded() {
        let ex = make()
        ex.recordRejection("   ")
        XCTAssertFalse(ex.isBlocked(""))
        XCTAssertFalse(ex.isBlocked("   "))
    }

    func testBlockedWordsListAndCount() {
        let ex = make()
        ex.recordRejection("one"); ex.recordRejection("one")   // blocked
        ex.recordRejection("two")                              // pending, not blocked
        XCTAssertEqual(ex.blockedWords(), ["one"])
        XCTAssertEqual(ex.count, 1)
    }

    func testUnblockRemovesAWord() {
        let ex = make()
        ex.recordRejection("one"); ex.recordRejection("one")
        ex.unblock("one")
        XCTAssertFalse(ex.isBlocked("one"))
        XCTAssertTrue(ex.blockedWords().isEmpty)
    }

    func testClearAll() {
        let ex = make()
        ex.recordRejection("one"); ex.recordRejection("one")
        ex.recordRejection("two"); ex.recordRejection("two")
        ex.clearAll()
        XCTAssertTrue(ex.blockedWords().isEmpty)
    }

    func testPersistsAcrossInstances() {
        let a = make(); a.recordRejection("okuo"); a.recordRejection("okuo")
        XCTAssertTrue(make().isBlocked("okuo"))
    }

    func testCapBoundsTheTrackedWords() {
        let ex = make(cap: 2)
        for w in ["one", "two", "three", "four"] {
            ex.recordRejection(w); ex.recordRejection(w)   // block each
        }
        XCTAssertLessThanOrEqual(ex.blockedWords().count, 2, "the list must stay bounded")
    }

    func testEvictionNeverDropsTheJustRecordedWord() {
        // At the cap, a fresh rejection enters at count 1 — strictly the lowest
        // when the incumbents hold 2 — so lowest-count eviction would drop the
        // just-recorded word every time, silently turning recordRejection into a
        // no-op that can never reach the block threshold. The word being recorded
        // must be exempt from eviction.
        let ex = make(cap: 3)
        for w in ["aa", "bb", "cc"] { ex.recordRejection(w); ex.recordRejection(w) }  // all count 2
        ex.recordRejection("dd")   // enters at 1, the strict minimum
        ex.recordRejection("dd")   // must build on the surviving count, reaching 2
        XCTAssertTrue(ex.isBlocked("dd"),
                      "the word being rejected right now must never be the eviction victim")
    }

    func testRemovalIsVisibleToAnotherInstance() {
        // The running controller and the Settings sheet are separate instances;
        // one removing a word must take effect for the other immediately.
        let controller = make()
        controller.recordRejection("akuo"); controller.recordRejection("akuo")
        XCTAssertTrue(controller.isBlocked("akuo"))

        make().unblock("akuo")   // "Settings" removes it
        XCTAssertFalse(controller.isBlocked("akuo"), "removal must be seen across instances")
    }
}
