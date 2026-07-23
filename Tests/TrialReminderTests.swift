import XCTest
@testable import FlicKey

// The pure end-of-trial reminder decision: fires at most once per threshold, in
// order, never repeats, and honors a late first launch by skipping thresholds the
// trial has already blown past.
final class TrialReminderTests: XCTestCase {

    // Above the most relaxed threshold: nothing yet.
    func testNoReminderEarlyInTrial() {
        let d = TrialReminder.decide(daysLeft: 30, lastLevel: 0)
        XCTAssertFalse(d.show)
        XCTAssertEqual(d.newLevel, 0)

        XCTAssertFalse(TrialReminder.decide(daysLeft: 8, lastLevel: 0).show)
    }

    // Reaching a week left fires the first (level 7) reminder once.
    func testFirstReminderAtSevenDays() {
        let d = TrialReminder.decide(daysLeft: 7, lastLevel: 0)
        XCTAssertTrue(d.show)
        XCTAssertEqual(d.newLevel, 7)
    }

    // Between 7 and 3 days left, having already shown level 7, we stay quiet.
    func testNoRepeatWithinSameThreshold() {
        for days in 4...7 {
            XCTAssertFalse(TrialReminder.decide(daysLeft: days, lastLevel: 7).show,
                           "should not repeat the level-7 reminder at \(days) days")
        }
    }

    // The full escalation 7 -> 3 -> 1, each firing exactly once as days shrink.
    func testEscalationFiresEachThresholdOnce() {
        let seven = TrialReminder.decide(daysLeft: 7, lastLevel: 0)
        XCTAssertTrue(seven.show); XCTAssertEqual(seven.newLevel, 7)

        let three = TrialReminder.decide(daysLeft: 3, lastLevel: seven.newLevel)
        XCTAssertTrue(three.show); XCTAssertEqual(three.newLevel, 3)

        let one = TrialReminder.decide(daysLeft: 1, lastLevel: three.newLevel)
        XCTAssertTrue(one.show); XCTAssertEqual(one.newLevel, 1)

        // The final threshold does not fire again.
        XCTAssertFalse(TrialReminder.decide(daysLeft: 1, lastLevel: one.newLevel).show)
    }

    // A user who does not launch until late in the trial skips straight to the
    // most urgent threshold they have reached, without a spurious level-7 popup.
    func testLateFirstLaunchSkipsPassedThresholds() {
        let d = TrialReminder.decide(daysLeft: 2, lastLevel: 0)
        XCTAssertTrue(d.show)
        XCTAssertEqual(d.newLevel, 3, "2 days left should land on the level-3 reminder")

        let last = TrialReminder.decide(daysLeft: 1, lastLevel: 0)
        XCTAssertTrue(last.show)
        XCTAssertEqual(last.newLevel, 1)
    }

    // Copy: correct pluralization, a "tomorrow" final push, and never an em dash.
    func testMessageCopy() {
        XCTAssertEqual(TrialReminder.message(daysLeft: 1).title, "1 day left in your FlicKey trial")
        XCTAssertEqual(TrialReminder.message(daysLeft: 7).title, "7 days left in your FlicKey trial")
        XCTAssertTrue(TrialReminder.message(daysLeft: 1).body.contains("tomorrow"))
        XCTAssertTrue(TrialReminder.message(daysLeft: 3).body.contains("No subscription"))

        for days in [1, 3, 7] {
            let m = TrialReminder.message(daysLeft: days)
            XCTAssertFalse(m.title.contains("\u{2014}"), "title must not contain an em dash")
            XCTAssertFalse(m.body.contains("\u{2014}"), "body must not contain an em dash")
        }
    }

    func testThresholdsAreDescendingAndPositive() {
        XCTAssertEqual(TrialReminder.thresholds, [7, 3, 1])
    }
}
