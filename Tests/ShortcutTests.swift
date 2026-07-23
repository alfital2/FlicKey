import XCTest
import Carbon

// Tests for building a Shortcut from a key event and for ShortcutStore
// persistence. Key events are synthesized headlessly via NSEvent.keyEvent.
final class ShortcutTests: XCTestCase {

    private func keyEvent(_ mods: NSEvent.ModifierFlags, chars: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
            windowNumber: 0, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
    }

    // MARK: - Shortcut.from(event:)

    func testOptionTwoMatchesDefault() {
        let s = Shortcut.from(keyEvent([.option], chars: "2", keyCode: 19))
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.keyCode, 19)
        XCTAssertEqual(s?.cgFlagsRaw, CGEventFlags.maskAlternate.rawValue)
        XCTAssertEqual(s?.label, "⌥2")
    }

    func testNoModifierIsRejected() {
        XCTAssertNil(Shortcut.from(keyEvent([], chars: "a", keyCode: 0)))
    }

    func testMultipleModifiersOrderedConventionally() {
        // Conventional display order is ⌃⌥⇧⌘ regardless of press order.
        let s = Shortcut.from(keyEvent([.command, .shift], chars: "k", keyCode: 40))
        XCTAssertEqual(s?.label, "⇧⌘K")
        let expected = CGEventFlags([.maskCommand, .maskShift]).rawValue
        XCTAssertEqual(s?.cgFlagsRaw, expected)
    }

    func testControlOptionLabel() {
        let s = Shortcut.from(keyEvent([.control, .option], chars: "f", keyCode: 3))
        XCTAssertEqual(s?.label, "⌃⌥F")
        XCTAssertEqual(s?.cgFlagsRaw, CGEventFlags([.maskControl, .maskAlternate]).rawValue)
    }

    func testIgnoresNonShortcutModifiers() {
        // Caps Lock / function shouldn't count as a required modifier.
        XCTAssertNil(Shortcut.from(keyEvent([.capsLock], chars: "x", keyCode: 7)))
    }

    // MARK: - ShortcutStore round-trip

    private let keys = ["conversionShortcut.keyCode", "conversionShortcut.flags", "conversionShortcut.label"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testDefaultWhenUnset() {
        XCTAssertEqual(ShortcutStore.current(), .default)
    }

    func testPersistsAndReloads() {
        let custom = Shortcut(keyCode: 40, cgFlagsRaw: CGEventFlags.maskCommand.rawValue, label: "⌘K")
        ShortcutStore.set(custom)
        XCTAssertEqual(ShortcutStore.current(), custom)
    }
}
