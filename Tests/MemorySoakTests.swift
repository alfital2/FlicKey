import XCTest

// Seeded soak of ConversationMemoryCore against an independent reference model of
// its apply/save/echo-suppress decisions. This is the subsystem behind the
// per-site and per-conversation memory (Teams/Slack/browser), where the subtle
// echo-suppression logic once caused the "Safari tab flip-flop" save-under-the-
// wrong-key bug. The reference predicts, for every operation, whether the core
// should apply a remembered layout and whether it should save the user's choice;
// any divergence is a real bug, reported with the seed.
final class MemorySoakTests: XCTestCase {

    func testConversationMemoryCoreSoak() {
        let keys = ["chatA", "chatB", "site1", nil as String?]
        let sources = ["ABC", "Hebrew-PC", "Russian"]
        let echoWindow: TimeInterval = 0.8

        Soak.run("memory-core") { rng, _ in
            var store: [String: String] = [:]          // the real backing store
            var vtime: TimeInterval = 1000              // virtual clock
            var currentSource = sources[0]              // what the OS reports "now"
            var applied: (source: String, key: String)? = nil   // captured from onApplied
            var saved: (source: String, key: String)? = nil     // captured from onSaved

            let core = ConversationMemoryCore(
                namespace: "soak",
                lookup: { _, key in store[key] },
                store: { source, _, key in store[key] = source },
                applySource: { currentSource = $0 },        // applying switches the OS layout
                currentSource: { currentSource },
                now: { vtime },
                echoWindow: echoWindow,
                onApplied: { source, key in applied = (source, key) },
                onSaved: { source, key in saved = (source, key) })

            // Reference model of the core's internal state.
            var refKey: String? = nil
            var refLastApplied: String? = nil
            var refLastAppliedAt: TimeInterval = 0
            var refSourceBeforeApply: String? = nil
            var refObservedAppliedSource = false

            var log: [String] = []
            let ops = rng.int(150..<500)
            for _ in 0..<ops {
                applied = nil; saved = nil
                var expectApplied: (String, String)? = nil
                var expectSaved: (String, String)? = nil

                switch rng.int(0..<100) {
                case 0..<40:   // enter a (possibly new, possibly nil) conversation
                    let k = rng.pick(keys)
                    let sourceBeforeEnter = currentSource
                    log.append("enter(\(k ?? "nil"))")
                    core.enter(key: k)
                    if k != refKey {
                        refKey = k
                        if let k, let src = store[k] {   // has remembered memory → apply
                            refSourceBeforeApply = sourceBeforeEnter
                            refObservedAppliedSource = refSourceBeforeApply == src
                            refLastApplied = src; refLastAppliedAt = vtime
                            expectApplied = (src, k)
                        }
                    }

                case 40..<80:  // the user changes layout, then the input monitor fires
                    let src = rng.pick(sources)
                    currentSource = src
                    log.append("switch(\(src))@\(vtime)")
                    core.inputChanged()
                    if let key = refKey {
                        let inEchoWindow = vtime - refLastAppliedAt < echoWindow
                        var echo = false
                        if inEchoWindow, refLastApplied == src {
                            refObservedAppliedSource = true
                            echo = true
                        } else if inEchoWindow, !refObservedAppliedSource,
                                  refSourceBeforeApply == src {
                            echo = true
                        }
                        if !echo {
                            refLastApplied = nil
                            refSourceBeforeApply = nil
                            refObservedAppliedSource = false
                            expectSaved = (src, key)
                        }
                    }

                case 80..<90:  // left the app
                    log.append("reset")
                    core.reset()
                    refKey = nil; refLastApplied = nil
                    refSourceBeforeApply = nil; refObservedAppliedSource = false

                default:       // time passes
                    let dt = Double(rng.int(0..<2000)) / 1000.0
                    vtime += dt
                    log.append("+\(dt)s")
                }

                if applied.map({ [$0.source, $0.key] }) != expectApplied.map({ [$0.0, $0.1] }) {
                    return "applied=\(String(describing: applied)) expected=\(String(describing: expectApplied))\nlast ops: \(log.suffix(15))"
                }
                if saved.map({ [$0.source, $0.key] }) != expectSaved.map({ [$0.0, $0.1] }) {
                    return "saved=\(String(describing: saved)) expected=\(String(describing: expectSaved))\nlast ops: \(log.suffix(15))"
                }
                // INVARIANT: after leaving the app, a layout change can never be
                // saved under a stale key (the mutual-safety invariant).
                if refKey == nil && saved != nil {
                    return "saved with no active conversation: \(saved!)\nlast ops: \(log.suffix(15))"
                }
            }
            return nil
        }
    }
}
