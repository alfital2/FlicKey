import XCTest

final class DiagnosticHashTests: XCTestCase {

    private let salt = "test-salt-A"

    func testStableForSameInputAndSalt() {
        XCTAssertEqual(DiagnosticHash.token("Alice Cohen", salt: salt),
                       DiagnosticHash.token("Alice Cohen", salt: salt))
    }

    func testDiffersForDifferentInput() {
        XCTAssertNotEqual(DiagnosticHash.token("Alice Cohen", salt: salt),
                          DiagnosticHash.token("Bob Levi", salt: salt))
    }

    func testDiffersForDifferentSalt() {
        // The salt is what makes the token un-guessable: the same name under a
        // different install salt must produce a different token.
        XCTAssertNotEqual(DiagnosticHash.token("Alice Cohen", salt: "salt-A"),
                          DiagnosticHash.token("Alice Cohen", salt: "salt-B"))
    }

    func testIsSixLowercaseHexCharacters() {
        let token = DiagnosticHash.token("anything", salt: salt)
        XCTAssertEqual(token.count, 6)
        XCTAssertTrue(token.allSatisfy { "0123456789abcdef".contains($0) }, "token was \(token)")
    }

    func testEmptyValueStillTokenizes() {
        XCTAssertEqual(DiagnosticHash.token("", salt: salt).count, 6)
    }

    func testSaltValueBoundaryIsUnambiguous() {
        // Without a separator, ("ab","c") and ("a","bc") would hash the same bytes.
        XCTAssertNotEqual(DiagnosticHash.token("c", salt: "ab"),
                          DiagnosticHash.token("bc", salt: "a"))
    }
}
