import XCTest

final class InputHintFilterTests: XCTestCase {

    func testMouseClicksAlwaysQualify() {
        XCTAssertTrue(InputHintFilter.isSwitchLikely(
            isKeyEvent: false, keyCode: 0, hasCommandOrControl: false))
    }

    func testCommandOrControlKeysQualify() {
        // ⌘1 (tab jump), Ctrl+Tab (next tab), ⌘K (Slack switcher)
        XCTAssertTrue(InputHintFilter.isSwitchLikely(
            isKeyEvent: true, keyCode: 18, hasCommandOrControl: true))
        XCTAssertTrue(InputHintFilter.isSwitchLikely(
            isKeyEvent: true, keyCode: 48, hasCommandOrControl: true))
        XCTAssertTrue(InputHintFilter.isSwitchLikely(
            isKeyEvent: true, keyCode: 40, hasCommandOrControl: true))
    }

    func testReturnAndKeypadEnterQualify() {
        // Committing a typed URL (⌘L then Return) or a chat-picker selection.
        XCTAssertTrue(InputHintFilter.isSwitchLikely(
            isKeyEvent: true, keyCode: 36, hasCommandOrControl: false))
        XCTAssertTrue(InputHintFilter.isSwitchLikely(
            isKeyEvent: true, keyCode: 76, hasCommandOrControl: false))
    }

    func testPlainTypingNeverQualifies() {
        // Ordinary letters, space, backspace: a typing burst must not probe.
        for keyCode: UInt16 in [0, 1, 12, 49, 51] {
            XCTAssertFalse(InputHintFilter.isSwitchLikely(
                isKeyEvent: true, keyCode: keyCode, hasCommandOrControl: false),
                "keyCode \(keyCode) should not trigger a probe")
        }
    }
}
