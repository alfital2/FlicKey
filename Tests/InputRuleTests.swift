import XCTest

final class InputRuleTests: XCTestCase {

    func testSourceRoundTrip() {
        let rule = InputRule.source("com.apple.keylayout.ABC")
        XCTAssertEqual(rule.storageValue, "com.apple.keylayout.ABC")
        XCTAssertEqual(InputRule(storage: rule.storageValue), rule)
    }

    func testAutoRoundTrip() {
        XCTAssertEqual(InputRule.auto.storageValue, "__auto__")
        XCTAssertEqual(InputRule(storage: "__auto__"), .auto)
    }

    func testUndefinedRoundTrip() {
        XCTAssertEqual(InputRule.undefined.storageValue, "__undefined__")
        XCTAssertEqual(InputRule(storage: "__undefined__"), .undefined)
    }

    func testEmptyStorageIsNil() {
        XCTAssertNil(InputRule(storage: ""))
    }

    func testAccessors() {
        XCTAssertEqual(InputRule.source("x").sourceID, "x")
        XCTAssertNil(InputRule.auto.sourceID)
        XCTAssertNil(InputRule.undefined.sourceID)
        XCTAssertTrue(InputRule.auto.isAuto)
        XCTAssertFalse(InputRule.source("x").isAuto)
        XCTAssertTrue(InputRule.undefined.isUndefined)
        XCTAssertFalse(InputRule.source("x").isUndefined)
    }

    func testFallbackSymbol() {
        XCTAssertEqual(InputRule.auto.fallbackSymbol, "globe")
        XCTAssertEqual(InputRule.source("x").fallbackSymbol, "keyboard")
    }
}
