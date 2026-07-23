import XCTest

final class TypingBufferCoreTests: XCTestCase {

    private func core(_ maxLength: Int = 120) -> TypingBufferCore {
        TypingBufferCore(maxLength: maxLength)
    }

    private func type(_ string: String, into c: inout TypingBufferCore) {
        for ch in string { c.apply(.printable(String(ch))) }
    }

    func testPrintableAccumulates() {
        var c = core()
        type("hi", into: &c)
        XCTAssertEqual(c.text, "hi")
    }

    func testBackspaceRemovesLast() {
        var c = core()
        type("abc", into: &c)
        c.apply(.backspace)
        XCTAssertEqual(c.text, "ab")
    }

    func testBackspaceOnEmptyNeverUnderflows() {
        var c = core()
        c.apply(.backspace)
        c.apply(.backspace)
        XCTAssertEqual(c.text, "")
    }

    func testBoundaryClears() {
        var c = core()
        type("abc", into: &c)
        c.apply(.boundary)
        XCTAssertEqual(c.text, "")
    }

    func testCapKeepsTheMostRecentCharacters() {
        var c = core(3)
        type("abcde", into: &c)
        XCTAssertEqual(c.text, "cde")
        XCTAssertEqual(c.text.count, 3)
    }

    func testAdoptReplacesBuffer() {
        var c = core()
        type("xyz", into: &c)
        c.adopt("hello")
        XCTAssertEqual(c.text, "hello")
    }

    func testResetClears() {
        var c = core()
        c.apply(.printable("q"))
        c.reset()
        XCTAssertEqual(c.text, "")
    }

    // The safety invariant the in-place-replace path relies on: whatever the
    // sequence of events, the buffer never holds more characters than were typed
    // since the last boundary, so the caller's "delete text.count" can never reach
    // past the user's own run.
    func testNeverHoldsMoreThanTypedSinceLastBoundary() {
        var c = core()
        var typedSinceBoundary = 0
        let script: [TypingBufferCore.Event] = [
            .printable("a"), .printable("b"), .backspace, .printable("c"),
            .boundary, .printable("d"), .backspace, .backspace, .printable("e"),
        ]
        for event in script {
            switch event {
            case .printable: typedSinceBoundary += 1
            case .backspace: typedSinceBoundary = max(0, typedSinceBoundary - 1)
            case .boundary: typedSinceBoundary = 0
            }
            c.apply(event)
            XCTAssertLessThanOrEqual(c.text.count, typedSinceBoundary)
        }
    }
}
