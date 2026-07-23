import Foundation

// A repeating main-run-loop timer that fires a callback on a fixed interval.
// Added in .common mode so it keeps firing while a menu or other tracking loop is
// open. Starting an already-running timer is a no-op; stopping invalidates and
// clears it. Shared by the per-site (TabMemory) and per-conversation
// (AppConversationMemory) controllers, which poll their frontmost app the same way.
final class PollTimer {
    private var timer: Timer?
    private let interval: TimeInterval
    private let onTick: () -> Void

    init(interval: TimeInterval, onTick: @escaping () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }
}
