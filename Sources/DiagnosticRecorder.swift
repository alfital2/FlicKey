import Foundation

// A bounded, in-memory ring buffer of recent diagnostic events. It is inert
// unless recording is enabled (checked on every log), so a user who never opts
// in pays nothing and stores nothing. Bounded two ways: a hard capacity (evict
// oldest) and, at read time, an age cutoff (drop entries older than maxAge). All
// side-effecting dependencies are injected so the buffer can be tested with a
// controlled clock and consent flag.
final class DiagnosticRecorder {

    private let capacity: Int
    private let maxAge: TimeInterval
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private let appVersion: String

    private var buffer: [DiagnosticEntry] = []
    private let lock = NSLock()

    init(capacity: Int = 500,
         maxAge: TimeInterval = 3600,
         isEnabled: @escaping () -> Bool = { DiagnosticConsent.isRecordingEnabled },
         now: @escaping () -> Date = { Date() },
         appVersion: String = DiagnosticRecorder.bundleVersion()) {
        self.capacity = max(1, capacity)
        self.maxAge = maxAge
        self.isEnabled = isEnabled
        self.now = now
        self.appVersion = appVersion
    }

    // Record an event. No-op (no allocation, no storage) when recording is off.
    func log(_ event: DiagnosticEvent) {
        guard isEnabled() else { return }
        let entry = DiagnosticEntry(at: now(), event: event, appVersion: appVersion)
        lock.lock(); defer { lock.unlock() }
        buffer.append(entry)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
    }

    // Age-trimmed copy of the buffer, oldest → newest.
    func snapshot() -> [DiagnosticEntry] {
        let cutoff = now().addingTimeInterval(-maxAge)
        lock.lock(); defer { lock.unlock() }
        return buffer.filter { $0.at >= cutoff }
    }

    // Forget everything (used when the user turns recording off).
    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffer.removeAll()
    }

    static func bundleVersion() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
