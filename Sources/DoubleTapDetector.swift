import AppKit

// Pure decision logic for "the user double-tapped Shift", isolated from NSEvent
// so it can be unit-tested. Feed it transitions in order; `shiftUp` returns true
// on the release that completes a valid double-tap.
//
// A valid tap = Shift pressed then released with (a) no intervening non-modifier
// key, (b) no other modifier held, (c) a short press duration. Two such taps
// within `window` fire the trigger. Any non-clean release clears the pending
// first tap, so "Shift+A … pause … Shift" can never pair into a false trigger.
struct DoubleTapStateMachine {
    var window: TimeInterval = 0.30        // max gap between the two taps
    var maxTapDuration: TimeInterval = 0.30 // a tap must be a quick press→release

    private var shiftDownAt: TimeInterval?  // when Shift went down (nil = up)
    private var interveningKey = false      // a non-Shift key happened during this hold
    private var lastTapAt: TimeInterval?    // release time of the previous clean tap

    mutating func shiftDown(otherMods: Bool, at time: TimeInterval) {
        if otherMods { reset(); return }
        shiftDownAt = time
        interveningKey = false
    }

    // A non-modifier key was pressed → Shift is acting as a modifier, not a tap.
    mutating func keyPressed() {
        interveningKey = true
        lastTapAt = nil
    }

    // Another modifier (⌘/⌥/⌃) became active → this Shift isn't a clean tap.
    mutating func otherModifierPressed() {
        interveningKey = true
        lastTapAt = nil
    }

    mutating func shiftUp(otherMods: Bool, at time: TimeInterval) -> Bool {
        defer { shiftDownAt = nil }
        guard let down = shiftDownAt, !interveningKey, !otherMods,
              time - down <= maxTapDuration else {
            lastTapAt = nil          // non-clean release breaks any pending pair
            return false
        }
        if let last = lastTapAt, time - last <= window {
            lastTapAt = nil
            return true              // second clean tap in time → fire
        }
        lastTapAt = time             // first clean tap; wait for the second
        return false
    }

    private mutating func reset() {
        shiftDownAt = nil
        interveningKey = false
        lastTapAt = nil
    }
}

// Thin adapter: turns the global keyboard event stream into state-machine calls.
// Global monitoring rides the app's Accessibility grant (the same one the
// conversion already needs); it observes only — it never consumes events.
final class DoubleTapDetector {
    var onTrigger: (() -> Void)?
    // Fired every time the watched modifier goes DOWN — i.e. at the earliest
    // possible hint that a double-tap may be coming. Used to pre-warm the click
    // sound hardware so the trigger's click plays with no first-play lag.
    var onWatchedDown: (() -> Void)?

    // Which modifier this detector watches for a clean double-tap. Default Shift
    // (the convert gesture); the revert detector is created with .option.
    private let modifier: NSEvent.ModifierFlags
    // Every modifier EXCEPT the watched one: holding any of these makes a tap
    // "dirty" (the watched key is acting as part of a combo, not a lone tap).
    private let otherModifierMask: NSEvent.ModifierFlags

    init(modifier: NSEvent.ModifierFlags = .shift) {
        self.modifier = modifier
        self.otherModifierMask =
            NSEvent.ModifierFlags([.command, .option, .control, .shift]).subtracting(modifier)
    }

    private var monitor: Any?
    private var machine = DoubleTapStateMachine()
    private var shiftWasDown = false

    func start() {
        guard monitor == nil else { return }
        machine = DoubleTapStateMachine()
        shiftWasDown = false
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let time = event.timestamp
        let mods = event.modifierFlags
        let watchedNow = mods.contains(modifier)
        let otherMods = !mods.intersection(otherModifierMask).isEmpty

        switch event.type {
        case .keyDown:
            machine.keyPressed()
        case .flagsChanged:
            if watchedNow && !shiftWasDown {
                onWatchedDown?()
                machine.shiftDown(otherMods: otherMods, at: time)
            } else if !watchedNow && shiftWasDown {
                if machine.shiftUp(otherMods: otherMods, at: time) { onTrigger?() }
            } else if otherMods {
                machine.otherModifierPressed()   // another modifier toggled while held
            }
            shiftWasDown = watchedNow
        default:
            break
        }
    }
}
