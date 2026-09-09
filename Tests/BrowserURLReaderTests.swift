import XCTest

final class BrowserURLReaderTests: XCTestCase {

    func testAccessibilityReadinessRetriesAreFastAndBounded() {
        var schedule = AccessibilityReadinessRetrySchedule()
        XCTAssertEqual(schedule.takeNextDelay(), 0.05)
        XCTAssertEqual(schedule.takeNextDelay(), 0.10)
        XCTAssertEqual(schedule.takeNextDelay(), 0.20)
        XCTAssertEqual(schedule.takeNextDelay(), 0.40)
        XCTAssertNil(schedule.takeNextDelay())
        XCTAssertEqual(schedule.attemptsIssued, 4)
    }

    func testAccessibilityReadinessRetriesResetForANewActivationOrHint() {
        var schedule = AccessibilityReadinessRetrySchedule()
        XCTAssertEqual(schedule.takeNextDelay(), 0.05)
        XCTAssertEqual(schedule.takeNextDelay(), 0.10)
        schedule.reset()
        XCTAssertEqual(schedule.attemptsIssued, 0)
        XCTAssertEqual(schedule.takeNextDelay(), 0.05)
    }

    func testAccessibilityCacheRetainsOnlyResolvedTabs() {
        XCTAssertTrue(AccessibilityURLCachePolicy.shouldCache(.value("https://youtube.com")))
        XCTAssertTrue(AccessibilityURLCachePolicy.shouldCache(.value("about:newtab")))
        XCTAssertTrue(AccessibilityURLCachePolicy.shouldCache(.blank))
        XCTAssertFalse(AccessibilityURLCachePolicy.shouldCache(.failed))
        XCTAssertFalse(AccessibilityURLCachePolicy.shouldCache(
            .value("chrome://global/content/commonDialog.xhtml")))
    }

    func testAccessibilitySelectionPrefersOuterPageOverLargerEmbeddedFrame() {
        let candidates = [
            AccessibilityWebAreaCandidateFacts(
                containsFocus: false, nestingDepth: 0, area: 0, order: 0),
            AccessibilityWebAreaCandidateFacts(
                containsFocus: false, nestingDepth: 1, area: 311 * 224, order: 1),
        ]
        XCTAssertEqual(AccessibilityWebAreaSelection.preferredIndex(in: candidates), 0)
    }

    func testAccessibilitySelectionPrefersOutermostFocusedPage() {
        let candidates = [
            AccessibilityWebAreaCandidateFacts(
                containsFocus: true, nestingDepth: 0, area: 800 * 600, order: 0),
            AccessibilityWebAreaCandidateFacts(
                containsFocus: true, nestingDepth: 1, area: 300 * 200, order: 1),
            AccessibilityWebAreaCandidateFacts(
                containsFocus: false, nestingDepth: 0, area: 1_200 * 900, order: 2),
        ]
        XCTAssertEqual(AccessibilityWebAreaSelection.preferredIndex(in: candidates), 0)
    }

    func testAccessibilitySelectionUsesAreaAmongPeerPages() {
        let candidates = [
            AccessibilityWebAreaCandidateFacts(
                containsFocus: false, nestingDepth: 0, area: 600 * 400, order: 0),
            AccessibilityWebAreaCandidateFacts(
                containsFocus: false, nestingDepth: 0, area: 1_000 * 700, order: 1),
        ]
        XCTAssertEqual(AccessibilityWebAreaSelection.preferredIndex(in: candidates), 1)
    }

    func testStripsSchemeAndWWW() {
        XCTAssertEqual(BrowserURLReader.host(from: "https://www.bankotsar.co.il/login?x=1"),
                       "bankotsar.co.il")
    }

    func testKeepsMeaningfulSubdomain() {
        XCTAssertEqual(BrowserURLReader.host(from: "https://mail.google.com/inbox"),
                       "mail.google.com")
    }

    func testHostNormalizesCaseAndDNSRootDot() {
        XCTAssertEqual(BrowserURLReader.host(from: "https://WWW.Example.COM./path"),
                       "example.com")
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

    func testClassifyFirefoxChromeDialogAsUnreadable() {
        // On cold launch Firefox can focus this browser-chrome AXWebArea and
        // temporarily hide the selected page from the accessibility tree. Its
        // `global` host is not a website and must not end recovery polling.
        XCTAssertEqual(
            BrowserURLReader.classify("chrome://global/content/commonDialog.xhtml"),
            .unreadable)
    }

    func testClassifyOtherHostedInternalSchemesAsUnreadable() {
        for url in [
            "resource://gre/modules/AppConstants.sys.mjs",
            "moz-extension://01234567-89ab-cdef-0123-456789abcdef/page.html",
            "file://localhost/tmp/index.html",
            "ftp://ftp.example.com/archive",
        ] {
            XCTAssertEqual(BrowserURLReader.classify(url), .unreadable,
                           "expected internal/non-web URL to be unreadable: \(url)")
        }
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
