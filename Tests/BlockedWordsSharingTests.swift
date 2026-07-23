import XCTest
@testable import FlicKey

// The opt-in blocked-words share decision: prompt only when the interval has
// elapsed AND there is a blocked word we have not offered before.
final class BlockedWordsSharingTests: XCTestCase {

    private let week = BlockedWordsSharing.interval

    func testPromptsWhenDueAndNewWordsExist() {
        let d = BlockedWordsSharing.decide(now: week + 1, lastPromptAt: 0,
                                           blocked: ["zoom", "acme"], alreadyOffered: [])
        XCTAssertTrue(d.shouldPrompt)
        XCTAssertEqual(d.newWords, ["acme", "zoom"])   // sorted
    }

    func testNoPromptBeforeIntervalElapses() {
        let d = BlockedWordsSharing.decide(now: 1000, lastPromptAt: 900,
                                           blocked: ["zoom"], alreadyOffered: [])
        XCTAssertFalse(d.shouldPrompt)
        XCTAssertEqual(d.newWords, ["zoom"])   // there IS a new word, just not due yet
    }

    func testNoPromptWhenNothingNew() {
        let d = BlockedWordsSharing.decide(now: week * 5, lastPromptAt: 0,
                                           blocked: ["zoom"], alreadyOffered: ["zoom"])
        XCTAssertFalse(d.shouldPrompt)
        XCTAssertTrue(d.newWords.isEmpty)
    }

    func testNoPromptWhenNoBlockedWords() {
        let d = BlockedWordsSharing.decide(now: week * 5, lastPromptAt: 0,
                                           blocked: [], alreadyOffered: [])
        XCTAssertFalse(d.shouldPrompt)
    }

    func testOnlyUnofferedWordsAreNew() {
        let d = BlockedWordsSharing.decide(now: week + 1, lastPromptAt: 0,
                                           blocked: ["a", "b", "c"], alreadyOffered: ["b"])
        XCTAssertTrue(d.shouldPrompt)
        XCTAssertEqual(d.newWords, ["a", "c"])
    }

    func testReportShowsWordsAndInstallIDNoEmDash() {
        let r = BlockedWordsSharing.report(words: ["acme", "zoom"],
                                           installID: "ID-123", appVersion: "0.4.8")
        XCTAssertTrue(r.subject.contains("0.4.8"))
        XCTAssertTrue(r.body.contains("acme"))
        XCTAssertTrue(r.body.contains("zoom"))
        XCTAssertTrue(r.body.contains("ID-123"))
        XCTAssertTrue(r.body.contains("Words: 2"))
        XCTAssertFalse(r.body.contains("\u{2014}"), "no em dashes in shared copy")
    }
}
