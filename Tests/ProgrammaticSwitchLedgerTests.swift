import XCTest

final class ProgrammaticSwitchLedgerTests: XCTestCase {
    private let en = "com.apple.keylayout.ABC"
    private let he = "com.apple.keylayout.Hebrew-PC"

    // The reported bug: Terminal forces English, WhatsApp (remembered Hebrew)
    // activates 70ms later, then Terminal's English echo arrives while WhatsApp
    // is frontmost. It must not be learned as WhatsApp's layout.
    func testEchoOfPreviousAppsSwitchIsIgnoredAfterNextAppActivates() {
        var ledger = ProgrammaticSwitchLedger()
        ledger.record(target: en, before: he, at: 10.00)   // Terminal
        ledger.record(target: he, before: en, at: 10.07)   // WhatsApp
        XCTAssertTrue(ledger.isEcho(en, at: 10.10))
        XCTAssertTrue(ledger.isEcho(he, at: 10.12))
        XCTAssertTrue(ledger.isEcho(en, at: 10.40))        // delayed settling duplicate
    }

    func testChangeAfterWindowIsGenuine() {
        var ledger = ProgrammaticSwitchLedger()
        ledger.record(target: he, before: en, at: 10.0)
        XCTAssertFalse(ledger.isEcho(en, at: 11.0))
    }

    func testUninvolvedSourceIsGenuineInsideWindow() {
        var ledger = ProgrammaticSwitchLedger()
        ledger.record(target: he, before: en, at: 10.0)
        XCTAssertFalse(ledger.isEcho("com.apple.keylayout.Russian", at: 10.1))
    }

    func testPreSwitchSourceIsGenuineOnceTargetWasObserved() {
        var ledger = ProgrammaticSwitchLedger()
        ledger.record(target: he, before: en, at: 10.0)
        XCTAssertTrue(ledger.isEcho(en, at: 10.01))        // in flight, still old
        XCTAssertTrue(ledger.isEcho(he, at: 10.02))        // switch landed
        XCTAssertFalse(ledger.isEcho(en, at: 10.3))        // user switched back
    }

    // Terminal's English request is still in flight when WhatsApp activates, so
    // the current source still reads Hebrew. WhatsApp must re-issue its switch.
    func testPendingTargetExposesInFlightSwitch() {
        var ledger = ProgrammaticSwitchLedger()
        ledger.record(target: en, before: he, at: 10.0)
        XCTAssertEqual(ledger.pendingTarget(at: 10.05), en)
        XCTAssertNil(ledger.pendingTarget(at: 11.0))
    }

    // A site/conversation core must not learn another owner's echo either.
    func testCoreIgnoresExternalEcho() {
        var stored: [String] = []
        var current = en
        let core = ConversationMemoryCore(
            namespace: "site",
            lookup: { _, _ in nil },
            store: { source, _, _ in stored.append(source) },
            applySource: { current = $0 },
            currentSource: { current },
            isExternalEcho: { $0 == self.en },
            now: { 0 })
        core.enter(key: "example.com")
        core.inputChanged()
        XCTAssertEqual(stored, [])
        current = he
        core.inputChanged()
        XCTAssertEqual(stored, [he])
    }
}
