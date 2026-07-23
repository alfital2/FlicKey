import AppKit
import ApplicationServices

// Event hints that make tab/chat detection feel instant. The browser (or Teams/
// Slack) announces a switch the moment it happens, through two public channels:
// an AX title-change notification on its window, and the user input that caused
// the switch (a click, or a shortcut like ⌘1/Ctrl+Tab). Each hint asks the owning
// controller to probe NOW instead of waiting for the next poll tick, cutting
// perceived latency from the poll interval (400 to 700ms) to under ~100ms.
//
// Hints are best-effort accelerators only. The repeating poll stays authoritative,
// because AX events are known to go silent in the field (Teams tears its AX tree
// down when backgrounded; see AppConversationMemory). A missed hint costs nothing
// beyond the old latency.
//
// Kill switch: `defaults write com.talalfi.FlicKey instantDetectionEnabled -bool NO`
// disables every hint at the next app activation, reverting to pure polling,
// so a field regression can be turned off without shipping a build.
enum DetectionHints {
    private static let key = "instantDetectionEnabled"

    static var isEnabled: Bool {
        AppDefaults.store.object(forKey: key) as? Bool ?? true   // absent → on
    }
}

// Decides whether an input event could plausibly have switched a tab or chat.
// Pure, so the filter is unit-testable. Mouse clicks always qualify (tab clicks,
// links, sidebar chats). Key presses qualify only with ⌘ or ⌃ held (⌘T, ⌘1-9,
// Ctrl+Tab, ⌘K) or on Return/keypad-Enter (committing a typed URL or a chat
// picker); plain typing never probes, so keystroke bursts cost nothing.
enum InputHintFilter {
    static func isSwitchLikely(isKeyEvent: Bool, keyCode: UInt16, hasCommandOrControl: Bool) -> Bool {
        guard isKeyEvent else { return true }
        if hasCommandOrControl { return true }
        return keyCode == 36 || keyCode == 76   // return, keypad enter
    }
}

// Fires onHint when the observed app changes a window title or its focused
// window. For browsers the window title is the page title, so a tab switch posts
// this within milliseconds. Same AXObserver lifecycle as AppFocusObserver
// (create, addNotification, run-loop source; balanced in stop()/deinit).
final class TitleChangeHint {

    var onHint: (() -> Void)?

    private let pid: pid_t
    private let appElement: AXUIElement
    private var observer: AXObserver?

    private static let notifications = [
        kAXTitleChangedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    init(pid: pid_t) {
        self.pid = pid
        self.appElement = AXUIElementCreateApplication(pid)
    }

    deinit { stop() }

    func start() {
        guard observer == nil else { return }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<TitleChangeHint>.fromOpaque(refcon).takeUnretainedValue()
            me.onHint?()
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.notifications {
            AXObserverAddNotification(obs, appElement, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    func stop() {
        guard let obs = observer else { return }
        for n in Self.notifications {
            AXObserverRemoveNotification(obs, appElement, n as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = nil
    }
}

// Fires onHint when the user performs input that could switch a tab or chat
// (per InputHintFilter). Observation only; events pass through untouched. The
// owning controller starts this while its app is frontmost and stops it on leave,
// so the monitors exist only when a probe could matter.
final class InputActivityHint {

    var onHint: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let watched: NSEvent.EventTypeMask =
        [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    deinit { stop() }

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.watched) {
            [weak self] event in self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.watched) {
            [weak self] event in self?.handle(event); return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        // NSEvent.keyCode raises for non-key events, so only key-downs may read it;
        // mouse events go through the filter with a placeholder code.
        let likely: Bool
        if event.type == .keyDown {
            likely = InputHintFilter.isSwitchLikely(
                isKeyEvent: true,
                keyCode: event.keyCode,
                hasCommandOrControl: !event.modifierFlags.intersection([.command, .control]).isEmpty)
        } else {
            likely = InputHintFilter.isSwitchLikely(
                isKeyEvent: false, keyCode: 0, hasCommandOrControl: false)
        }
        if likely { onHint?() }
    }
}
