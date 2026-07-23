import XCTest

// Deterministic soak/fuzz infrastructure. Each soak drives a real component with
// a seeded random event stream and checks invariants after every step; any
// failure is reported with the exact seed so it reproduces 100%.
//
// Run modes:
//   default            — a bounded iteration count, fast enough for CI.
//   SOAK_ITERATIONS=N  — override the iteration count.
//   SOAK_SECONDS=600   — run for that many wall-clock seconds instead (the
//                        "10 full minutes" mode: SOAK_SECONDS=600).

// SplitMix64: a tiny, fast, fully deterministic PRNG. Same seed ⇒ same stream on
// every machine, which is what makes a failure reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: Range<Int>) -> Int {
        Int(next() % UInt64(range.count)) + range.lowerBound
    }
    mutating func chance(_ oneIn: Int) -> Bool { next() % UInt64(oneIn) == 0 }
    mutating func pick<T>(_ xs: [T]) -> T { xs[int(0..<xs.count)] }
}

enum Soak {
    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
    static var iterations: Int { env("SOAK_ITERATIONS").flatMap(Int.init) ?? 3_000 }

    // The timed ("10 full minutes") duration. Read from a FILE, because xcodebuild
    // sanitizes environment variables before the hosted test runner sees them, so
    // an env var is unreliable. To run the full soak:
    //   echo 600 > /tmp/flickey-soak-seconds
    //   xcodebuild test -only-testing:FlicKeyTests/DetectionSoakTests ... (+ the others)
    //   rm /tmp/flickey-soak-seconds
    static let durationFile = "/tmp/flickey-soak-seconds"
    static var seconds: Double? {
        if let s = env("SOAK_SECONDS").flatMap(Double.init) { return s }
        guard let raw = try? String(contentsOfFile: durationFile, encoding: .utf8) else { return nil }
        return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Runs `session` repeatedly, each with its own reproducible seed. `session`
    // returns nil on success or a failure description on an invariant violation;
    // the runner then fails with the exact seed to reproduce, and stops.
    // `maxIterations` caps the bounded (non-timed) run for soaks whose sessions are
    // individually expensive (e.g. disk-backed). It never limits the timed
    // (SOAK_SECONDS) mode — a 10-minute soak still runs the full duration.
    static func run(_ name: String, maxIterations: Int? = nil, base: UInt64 = 0xF11C_5EED,
                    file: StaticString = #filePath, line: UInt = #line,
                    _ session: (inout SeededGenerator, Int) -> String?) {
        let start = Date()
        let limit = maxIterations.map { min($0, iterations) } ?? iterations
        var i = 0
        while true {
            let seed = base &+ UInt64(i)
            var rng = SeededGenerator(seed: seed)
            if let failure = session(&rng, i) {
                XCTFail("[\(name)] invariant broken at iteration \(i) (seed=\(seed)):\n\(failure)",
                        file: file, line: line)
                return
            }
            i += 1
            if let secs = seconds {
                if Date().timeIntervalSince(start) >= secs { break }
            } else if i >= limit {
                break
            }
        }
    }
}
