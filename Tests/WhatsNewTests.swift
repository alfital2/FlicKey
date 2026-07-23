import XCTest
@testable import FlicKey

// The one-time "what's new" gate: show only when the developer set a note and the
// user has not already seen that note's version.
final class WhatsNewTests: XCTestCase {

    private let note = WhatsNewNote(version: "1.0", title: "T", subtitle: "S",
                                    items: [WhatsNewItem(symbol: "star", text: "b")])

    func testNoNoteNeverShows() {
        XCTAssertFalse(WhatsNew.shouldShow(current: nil, seenVersion: nil))
        XCTAssertFalse(WhatsNew.shouldShow(current: nil, seenVersion: "1.0"))
    }

    func testShowsWhenUnseen() {
        XCTAssertTrue(WhatsNew.shouldShow(current: note, seenVersion: nil))
        XCTAssertTrue(WhatsNew.shouldShow(current: note, seenVersion: "0.9"))
    }

    func testDoesNotRepeatOnceSeen() {
        XCTAssertFalse(WhatsNew.shouldShow(current: note, seenVersion: "1.0"))
    }

    func testBumpingVersionShowsAgain() {
        let next = WhatsNewNote(version: "1.1", title: "T2", subtitle: "S2",
                                items: [WhatsNewItem(symbol: "star", text: "b")])
        XCTAssertTrue(WhatsNew.shouldShow(current: next, seenVersion: "1.0"))
    }

    // The shipped note must not carry an em dash (house style), and should lead
    // with the auto-fix upgrade plus haptics and sound.
    func testShippedNoteContentAndStyle() {
        guard let current = WhatsNew.current else { return XCTFail("expected a shipped note") }
        let allText = ([current.title, current.subtitle] + current.items.map(\.text)).joined(separator: " ").lowercased()
        XCTAssertTrue(allText.contains("auto-fix"), "should headline the auto-fix upgrade")
        XCTAssertTrue(allText.contains("haptic"), "should mention haptics")
        XCTAssertTrue(allText.contains("hear") || allText.contains("sound") || allText.contains("click"),
                      "should mention the sound")
        for piece in [current.title, current.subtitle] + current.items.map(\.text) {
            XCTAssertFalse(piece.contains("\u{2014}"), "no em dashes in what's new copy")
        }
    }
}
