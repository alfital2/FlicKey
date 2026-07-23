import Foundation

// Pure decision for the "FlicKey has helped you N times" nudge, shown to
// non-licensed users each time the running total crosses another `interval`
// switches. Returns the milestone just crossed, or nil. No UI, so it is testable.
enum StatsNag {
    static let interval = 1000

    // `lastNagged` is the highest milestone already shown (0 = none). Fire when the
    // total has reached a higher multiple of `interval` than that.
    static func milestone(total: Int, lastNagged: Int) -> Int? {
        let floor = (total / interval) * interval
        return (floor >= interval && floor > lastNagged) ? floor : nil
    }
}
