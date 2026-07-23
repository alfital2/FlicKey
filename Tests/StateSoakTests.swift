import XCTest

// Seeded soaks of the two persistent state machines: the entitlement decision
// (paywall) and the learned-exceptions store. Both are places where a subtle
// state bug would be near-impossible to notice by hand but costly in the field.
final class StateSoakTests: XCTestCase {

    // MARK: - Entitlement: monotonic, licensed-wins, grandfather-stable.

    func testEntitlementMonotonicitySoak() {
        let day = 24 * 60 * 60
        Soak.run("entitlement") { rng, _ in
            let cutoff = 1_000_000
            let firstRun = cutoff + rng.int(-3 * day..<3 * day)   // straddle the cutoff
            let isLicensed = rng.chance(4)

            // Sweep time forward with a ratcheting maxElapsed, exactly as the app
            // does, and assert the entitlement only ever moves in the allowed
            // direction (never regenerates trial days, never revives once expired).
            var maxElapsed = 0
            var now = firstRun
            var prevDaysLeft = Int.max
            var everExpired = false

            for _ in 0..<200 {
                now += rng.int(0..<2 * day)
                maxElapsed = max(maxElapsed, now - firstRun)
                let state = Entitlement.decide(
                    trial: TrialState(firstRun: firstRun, maxElapsed: maxElapsed, lastNag: 0),
                    now: now, isLicensed: isLicensed, cutoff: cutoff)

                if isLicensed && state != .licensed {
                    return "licensed user resolved to \(state)"
                }
                if !isLicensed && firstRun < cutoff && state != .grandfathered {
                    return "pre-cutoff user not grandfathered: \(state)"
                }
                if state.coreEnabled != (state != .expired) {
                    return "coreEnabled inconsistent for \(state)"
                }
                if case .trial(let daysLeft) = state {
                    if daysLeft > prevDaysLeft {
                        return "trial days went UP: \(prevDaysLeft) → \(daysLeft)"
                    }
                    if daysLeft < 1 || daysLeft > 30 { return "trial daysLeft out of range: \(daysLeft)" }
                    prevDaysLeft = daysLeft
                }
                if state == .expired { everExpired = true }
                // Once expired (and unlicensed), advancing time can never revive.
                if everExpired && !isLicensed && state != .expired && state != .grandfathered {
                    return "revived after expiry: \(state)"
                }
            }
            return nil
        }
    }

    // MARK: - AutoSwitchExceptions: block only after threshold, acceptance resets,
    // cap bounds the store — differential against a reference count map.

    func testExceptionsDifferentialSoak() {
        let words = ["nv", "vnmc", "akuo", "susu", "i", "hello"]
        // One reused disk-backed suite (creating a fresh domain per iteration is
        // slow); it is cleared at the start of every session for independence. A
        // lower bounded cap keeps CI fast; the timed soak still runs the full time.
        let suite = "soak.exceptions"
        guard let store = UserDefaults(suiteName: suite) else { return XCTFail("no store") }
        defer { store.removePersistentDomain(forName: suite) }

        Soak.run("exceptions", maxIterations: 400) { rng, _ in
            store.removePersistentDomain(forName: suite)

            // Cap comfortably above the distinct-word count so eviction never
            // fires here: which equal-count word gets evicted at the cap is
            // deliberately unspecified (covered by dedicated unit tests), so the
            // differential would over-specify it. This soak targets the
            // threshold / acceptance / unblock / normalization interplay instead.
            let cap = 50
            let ex = AutoSwitchExceptions(store: store, blockThreshold: 2, cap: cap)
            var ref: [String: Int] = [:]   // normalized word → rejection count
            var log: [String] = []

            let ops = rng.int(80..<250)
            for _ in 0..<ops {
                let w = rng.pick(words)
                let n = w.lowercased()
                switch rng.int(0..<100) {
                case 0..<50:
                    ex.recordRejection(w); log.append("reject(\(w))")
                    ref[n, default: 0] += 1
                case 50..<75:
                    ex.recordAcceptance(w); log.append("accept(\(w))")
                    if ref[n] != nil { ref[n] = 0 }
                default:
                    ex.unblock(w); log.append("unblock(\(w))")
                    if ref[n] != nil { ref[n] = 0 }
                }

                // INVARIANT: blocked iff the reference count reached the threshold.
                let expectBlocked = (ref[n] ?? 0) >= 2
                if ex.isBlocked(w) != expectBlocked {
                    return "isBlocked(\(w))=\(ex.isBlocked(w)) expected=\(expectBlocked) (refCount=\(ref[n] ?? 0))\nlast ops: \(log.suffix(15))"
                }
                // INVARIANT: the blocked list never exceeds the cap.
                if ex.count > cap {
                    return "blocked count \(ex.count) exceeds cap \(cap)\nlast ops: \(log.suffix(15))"
                }
            }
            return nil
        }
    }
}
