import XCTest

final class BrowserURLReaderTests: XCTestCase {

    func testStripsSchemeAndWWW() {
        XCTAssertEqual(BrowserURLReader.host(from: "https://www.bankotsar.co.il/login?x=1"),
                       "bankotsar.co.il")
    }

    func testKeepsMeaningfulSubdomain() {
        XCTAssertEqual(BrowserURLReader.host(from: "https://mail.google.com/inbox"),
                       "mail.google.com")
    }

    func testPlainDomainWithPathAndQuery() {
        XCTAssertEqual(BrowserURLReader.host(from: "https://youtube.com/watch?v=abc"),
                       "youtube.com")
    }

    func testHTTPScheme() {
        XCTAssertEqual(BrowserURLReader.host(from: "http://example.com"), "example.com")
    }

    func testInvalidInputsReturnNil() {
        XCTAssertNil(BrowserURLReader.host(from: "not a url"))
        XCTAssertNil(BrowserURLReader.host(from: ""))
        XCTAssertNil(BrowserURLReader.host(from: "about:blank"))
    }

    // MARK: - Tab classification (site / new-tab / unreadable)

    func testClassifyRealSite() {
        XCTAssertEqual(BrowserURLReader.classify("https://www.youtube.com/watch?v=abc"),
                       .site("youtube.com"))
        XCTAssertEqual(BrowserURLReader.classify("https://bankleumi.co.il"),
                       .site("bankleumi.co.il"))
    }

    func testClassifyNewTabURLs() {
        // A browser's internal new-tab page (Chrome/Edge/Brave/Arc + about:) →
        // newTab, so the new-tab preference (not the prior site) applies.
        for url in ["chrome://newtab/", "chrome://new-tab-page/",
                    "edge://newtab/", "brave://newtab/",
                    "about:blank", "about:newtab", "about:home",
                    "about:privatebrowsing",
                    "favorites://"] {
            XCTAssertEqual(BrowserURLReader.classify(url), .newTab, "expected newTab for '\(url)'")
        }
    }

    func testClassifyUntrackedInternalPageIsUnreadable() {
        // A readable-but-not-a-website page we don't key on → keep prior, don't
        // invent a bogus site key from it.
        XCTAssertEqual(BrowserURLReader.classify("garbage with spaces"), .unreadable)
        // Reader mode represents a real site but does not itself have a host.
        // Preserve the prior key rather than storing an internal about: key.
        XCTAssertEqual(BrowserURLReader.classify("about:reader?url=https://example.com"),
                       .unreadable)
    }

    // MARK: - Read result → state (the missing-value-vs-error distinction)

    func testBlankReadIsNewTab() {
        // Safari returns AppleScript `missing value` for a blank tab (ReadResult
        // .blank). That is a definite new tab, NOT a failed read.
        XCTAssertEqual(BrowserURLReader.state(from: .blank), .newTab)
    }

    func testFailedReadKeepsPriorTab() {
        // A script error must never be mistaken for a blank tab.
        XCTAssertEqual(BrowserURLReader.state(from: .failed), .unreadable)
    }

    func testValueReadIsClassified() {
        XCTAssertEqual(BrowserURLReader.state(from: .value("https://youtube.com")),
                       .site("youtube.com"))
        XCTAssertEqual(BrowserURLReader.state(from: .value("chrome://newtab/")), .newTab)
    }
}
