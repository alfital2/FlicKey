import XCTest

// Regression guard for the search-field routing fix. The Spotlight off-by-one
// bug shipped because nothing exercised the "how do I replace" decision: search
// fields must replace the WHOLE field (select-all + type) from the FIELD's text,
// while plain fields backspace the keystroke buffer. These pin that decision so
// it can't silently regress.
final class ConversionRouterTests: XCTestCase {

    // Search field → select-all replace, converting the FIELD's text (here the
    // full "asdasd") rather than the shorter keystroke buffer ("asd"). If someone
    // deletes the search-field branch, the plan becomes .backspaceReplace and
    // this fails.
    func testSearchFieldReplacesWholeFieldFromItsValue() {
        let plan = ConversionRouter.replacePlan(typed: "asd", searchFieldValue: "asdasd")
        guard case let .searchReplace(text, _)? = plan else {
            return XCTFail("search field should route to .searchReplace, got \(String(describing: plan))")
        }
        XCTAssertEqual(text, ConversionRouter.convertText("asdasd").converted,
                       "must convert the field's text")
        XCTAssertNotEqual(text, ConversionRouter.convertText("asd").converted,
                          "must NOT convert the (shorter) keystroke buffer")
    }

    // Plain field → in-place backspace of exactly what the user typed.
    func testPlainFieldBackspacesTheKeystrokeBuffer() {
        let plan = ConversionRouter.replacePlan(typed: "akuo", searchFieldValue: nil)
        guard case let .backspaceReplace(count, text, _)? = plan else {
            return XCTFail("plain field should route to .backspaceReplace, got \(String(describing: plan))")
        }
        XCTAssertEqual(count, 4, "delete exactly the typed run length")
        XCTAssertEqual(text, ConversionRouter.convertText("akuo").converted)
    }

    // Nothing typed → no plan (smartConvert falls through to its AX/clipboard
    // fallbacks), even when a search field has a value.
    func testEmptyBufferProducesNoPlan() {
        XCTAssertNil(ConversionRouter.replacePlan(typed: "", searchFieldValue: nil))
        XCTAssertNil(ConversionRouter.replacePlan(typed: "", searchFieldValue: "asdasd"))
    }

    // A search field reporting an empty value falls back to the buffer path
    // rather than replacing the field with nothing.
    func testEmptySearchValueFallsBackToBuffer() {
        let plan = ConversionRouter.replacePlan(typed: "akuo", searchFieldValue: "")
        guard case let .backspaceReplace(count, _, _)? = plan else {
            return XCTFail("empty search value should fall back to .backspaceReplace, got \(String(describing: plan))")
        }
        XCTAssertEqual(count, 4)
    }
}
