import AppKit
import XCTest

final class TypingBufferTests: XCTestCase {

    private func keyEvent(_ characters: String, keyCode: UInt16 = 0,
                          flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    // MARK: - Multi-character keystrokes (QA ARABIC-1: ArabicPC b → لا)

    func testMultiCharacterKeystrokeIsBuffered() {
        // One physical key, two characters. Dropping it desynced the ⇧⇧ buffer
        // from the screen ("bad" → لاشي → ⇧⇧ produced "لاad").
        XCTAssertEqual(TypingBuffer.semanticEvent(for: keyEvent("لا", keyCode: 11)),
                       .printable("لا"))
    }

    func testSingleCharacterKeystrokeStillBuffers() {
        XCTAssertEqual(TypingBuffer.semanticEvent(for: keyEvent("a")), .printable("a"))
    }

    func testControlCharactersAreStillIgnored() {
        XCTAssertNil(TypingBuffer.semanticEvent(for: keyEvent("\u{01}")))
    }

    func testCommandChordIsABoundary() {
        XCTAssertEqual(TypingBuffer.semanticEvent(for: keyEvent("a", flags: .command)),
                       .boundary)
    }

    // The buffer's length stays symmetric with the on-screen field: a لا keystroke
    // adds two Characters, and each backspace removes one Character — exactly what
    // the field does.
    func testBufferLengthMatchesScreenForDigraphKeystroke() {
        var core = TypingBufferCore()
        core.apply(.printable("لا"))   // the b key
        core.apply(.printable("ش"))    // a
        core.apply(.printable("ي"))    // d
        XCTAssertEqual(core.text, "لاشي")
        XCTAssertEqual(core.text.count, 4, "buffer must count what the SCREEN holds")
        core.apply(.backspace)
        XCTAssertEqual(core.text, "لاش", "backspace removes one Character, like the field")
    }
}
