import XCTest

// Smoke tests for the live macOS input-source layer. These assert invariants
// that hold on any real Mac (≥1 enabled keyboard layout) rather than specific
// layouts, so they stay deterministic across machines.
final class InputSourceTests: XCTestCase {

    func testEnabledSourcesNotEmpty() {
        XCTAssertFalse(InputSourceCatalog.enabledSources().isEmpty)
    }

    func testEachSourceHasIDAndName() {
        for source in InputSourceCatalog.enabledSources() {
            XCTAssertFalse(source.id.isEmpty)
            XCTAssertFalse(source.localizedName.isEmpty)
        }
    }

    func testLocalizedNameLookupMatchesCatalog() {
        guard let first = InputSourceCatalog.enabledSources().first else { return }
        XCTAssertEqual(InputSourceCatalog.localizedName(for: first.id), first.localizedName)
    }

    func testCurrentSourceCodeIsTwoLettersOrUnknown() {
        let code = InputSourceManager.currentSourceCode()
        XCTAssertFalse(code.isEmpty)
        XCTAssertLessThanOrEqual(code.count, 2)
    }
}
