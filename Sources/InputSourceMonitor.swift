import Foundation
import Carbon

// Fires whenever the system keyboard input source changes. Event-driven via the
// distributed notification kTISNotifySelectedKeyboardInputSourceChanged.
final class InputSourceMonitor {

    var onChange: (() -> Void)?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<InputSourceMonitor>.fromOpaque(observer).takeUnretainedValue()
                monitor.onChange?()
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let center = CFNotificationCenterGetDistributedCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }
}
