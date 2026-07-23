import XCTest

final class RoundTripTests: XCTestCase {
    func testEnToHe() { XCTAssertEqual(ConversionEngine.convert("abc").converted, "שנב") }
    func testHeToEn() { XCTAssertEqual(ConversionEngine.convert("שנב").converted, "abc") }
    func testHebrewPhraseToWorks() { XCTAssertEqual(ConversionEngine.convert("'םרלד").converted, "works") }
    func testEnglishToGarage() { XCTAssertEqual(ConversionEngine.convert("dtrtdw").converted, "גאראג'") }
}
