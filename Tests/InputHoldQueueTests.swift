import XCTest

final class InputHoldQueueTests: XCTestCase {
    func testCapturedKeysStayOrderedThroughReplay() {
        var queue = InputHoldQueue<String>()
        XCTAssertTrue(queue.begin())
        XCTAssertTrue(queue.capture("a-down"))
        XCTAssertTrue(queue.capture("a-up"))
        XCTAssertEqual(queue.drain(), ["a-down", "a-up"])
        XCTAssertTrue(queue.capture("b-down"))
        XCTAssertEqual(queue.didReplay(), [])
        XCTAssertEqual(queue.didReplay(), ["b-down"])
        XCTAssertEqual(queue.didReplay(), [])
        XCTAssertFalse(queue.isHolding)
    }

    func testFailedEditStillReleasesEveryCapturedKey() {
        var queue = InputHoldQueue<Int>()
        XCTAssertTrue(queue.begin())
        XCTAssertTrue(queue.capture(1))
        XCTAssertTrue(queue.capture(2))
        XCTAssertEqual(queue.drain(), [1, 2])
        XCTAssertEqual(queue.didReplay(), [])
        XCTAssertEqual(queue.didReplay(), [])
        XCTAssertFalse(queue.isHolding)
    }

    func testStopReturnsUnpostedTailDuringReplay() {
        var queue = InputHoldQueue<Int>()
        XCTAssertTrue(queue.begin())
        XCTAssertTrue(queue.capture(1))
        XCTAssertEqual(queue.drain(), [1])
        XCTAssertTrue(queue.capture(2))
        XCTAssertEqual(queue.stop(), [2])
        XCTAssertFalse(queue.isHolding)
    }

    func testTenThousandCapturedKeysAreNeitherDroppedNorDuplicated() {
        var queue = InputHoldQueue<Int>()
        XCTAssertTrue(queue.begin())
        var delivered: [Int] = []
        var inFlight: [Int] = []
        for key in 0..<10_000 {
            if !queue.isHolding { XCTAssertTrue(queue.begin()) }
            XCTAssertTrue(queue.capture(key))
            if inFlight.isEmpty { inFlight = queue.drain() }
            if key % 3 == 0, !inFlight.isEmpty {
                delivered.append(inFlight.removeFirst())
                inFlight += queue.didReplay()
            }
        }
        while !inFlight.isEmpty {
            delivered.append(inFlight.removeFirst())
            inFlight += queue.didReplay()
        }
        XCTAssertEqual(delivered, Array(0..<10_000))
        XCTAssertFalse(queue.isHolding)
    }

    func testCapsLockLayoutLookupForReplay() throws {
        let abc = try XCTUnwrap(LayoutMap.forSource("com.apple.keylayout.ABC"))
        XCTAssertEqual(abc.character(forKeyCode: 0, shift: false), "a")
        XCTAssertEqual(abc.character(forKeyCode: 0, shift: false, capsLock: true), "A")
        // ABC's UCKeyTranslate table on current macOS returns uppercase for
        // Shift+Caps Lock too; it is not safe to assume the modifiers invert.
        XCTAssertEqual(abc.character(forKeyCode: 0, shift: true, capsLock: true), "A")
    }
}
