import AppKit

// Plays the layout-switch cue — N trackpad taps (+ optionally N clicks) —
// whenever the effective input source changes: app switch (app rules),
// browser tab switch (per-site memory), Slack/Teams conversation switch
// (per-conversation memory), or a manual ⌘Space. Each layout has its own
// tap count (1–3, or Off) in settings; the click count always mirrors the
// tap count. The decision itself (settle-debounce of rapid flip-flops, Off
// layouts, conversion suppression) is LayoutCueCore — unit tested; this shell
// owns the monitor, the taps-per-layout lookup, and the haptic/audio output.
//
// Haptics go through TrackpadActuator (private MultitouchSupport API), which
// taps the trackpad even when no finger is touching it. If that API is ever
// unavailable, the NSHapticFeedbackManager fallback still works — but only
// while a finger rests on the trackpad.
final class LayoutCueController {

    private let monitor = InputSourceMonitor()
    private var core = LayoutCueCore(initialSourceID: nil)

    func start() {
        core = LayoutCueCore(initialSourceID: InputSourceManager.currentSourceID())
        monitor.onChange = { [weak self] in self?.sourceChanged() }
        monitor.start()
    }

    // Conversion path: the double-shift fix switches the source itself and
    // already plays its own click — mute the cue for the switch it causes.
    func suppress() {
        core.suppress(for: 1.0, now: ProcessInfo.processInfo.systemUptime)
    }

    // The tap count configured for a layout (nil = Off / no cue), defaulting by
    // the layout's language so English/Hebrew users get 1/2 taps out of the box.
    static func tapCount(forSourceID id: String) -> Int? {
        let code = InputSourceCatalog.enabledSources()
            .first { $0.id == id }?.languageCodes.first
        let n = LayoutCueSettings.tapCount(forSourceID: id, defaultLanguageCode: code)
        return n == 0 ? nil : n
    }

    // A change notification restarts the settle timer; the cue decision runs
    // only after the burst goes quiet, so a rapid flip-flop (FlicKey's own
    // switch cascade) yields ONE cue for the final layout instead of
    // overlapping cues per notification.
    private static let settleDelay: TimeInterval = 0.25
    private var pendingSettle: DispatchWorkItem?

    private func sourceChanged() {
        core.noteChange(to: InputSourceManager.currentSourceID())
        pendingSettle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settleNow() }
        pendingSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func settleNow() {
        pendingSettle = nil
        guard let count = core.settle(tapCount: { Self.tapCount(forSourceID: $0) },
                                      now: ProcessInfo.processInfo.systemUptime) else { return }
        Self.play(count: count,
                  haptic: LayoutCueSettings.hapticEnabled,
                  sound: LayoutCueSettings.soundEnabled)
    }

    // Also called by the Settings pane to preview a cue (passes the toggles
    // it wants to demonstrate, regardless of what's currently enabled).
    static func play(count: Int, haptic: Bool, sound: Bool) {
        // A closed lid (clamshell) means the built-in trackpad is shut: the tap
        // can't be felt and the actuator may not fire, so drop the haptic. Sound is
        // unaffected. Read once here, not per tap, since a burst is only ~0.2s.
        let hapticNow = haptic && !LidState.isClosed
        guard hapticNow || sound else { return }
        let actuationID = LayoutCueSettings.actuationID(forLevel: LayoutCueSettings.hapticIntensityLevel)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                if hapticNow, !TrackpadActuator.shared.tap(actuationID: actuationID) {
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.generic, performanceTime: .now)
                }
                if sound { SoundEffect.playCueClick() }
            }
        }
    }
}
