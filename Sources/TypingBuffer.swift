import AppKit

// Pure typing-run state machine, isolated from NSEvent so it can be unit-tested
// (the same core/shell split as DoubleTapStateMachine↔DoubleTapDetector). It holds
// the text immediately before the caret. Feed it semantic events; a `.boundary`
// (anything that moves the caret out of the contiguous run) clears it, so the
// buffer can only ever hold characters the user actually typed and synthetic
// backspaces can never over-delete.
struct TypingBufferCore {
    private(set) var text = ""
    private let maxLength: Int

    init(maxLength: Int = 120) { self.maxLength = maxLength }

    enum Event: Equatable {
        case printable(String)   // one visible glyph, as it appears
        case backspace           // delete the last character
        case boundary            // caret left the run; clear the buffer
    }

    mutating func apply(_ event: Event) {
        switch event {
        case .printable(let glyph):
            text += glyph
            if text.count > maxLength { text.removeFirst(text.count - maxLength) }
        case .backspace:
            if !text.isEmpty { text.removeLast() }
        case .boundary:
            text = ""
        }
    }

    // Clear the buffer (caret moved, app switched).
    mutating func reset() { text = "" }

    // Adopt an externally supplied value as the new run, so an immediate re-trigger
    // cycles and continued typing extends it.
    mutating func adopt(_ newValue: String) { text = newValue }
}

// Tracks the run of characters the user has just typed into the current field, so
// the fix can replace it instantly (no clipboard, no selection) by deleting
// text.count characters and retyping the conversion. The decision logic lives in
// TypingBufferCore; this shell only translates NSEvents into semantic events and
// owns the monitor lifecycle.
final class TypingBuffer {

    private var core = TypingBufferCore()
    var text: String { core.text }

    private var monitor: Any?
    private var localMonitor: Any?
    private var workspaceToken: NSObjectProtocol?
    private var suspended = false        // ignore our own synthetic edits

    private static let watched: NSEvent.EventTypeMask =
        [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    func start() {
        guard monitor == nil else { return }
        // Global monitor: keystrokes in OTHER apps. Global monitors deliberately do
        // NOT receive events sent to our own app, so ⇧⇧ conversion wouldn't work in
        // FlicKey's own text fields (Settings search, license key). A LOCAL monitor
        // covers those; pass the event through unchanged so the field still gets it.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: Self.watched) {
            [weak self] event in self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.watched) {
            [weak self] event in self?.handle(event); return event
        }
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reset() }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
        if let workspaceToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
        }
        workspaceToken = nil
    }

    deinit { stop() }

    func reset() { core.reset() }

    // Wrap our own synthetic backspace/retype so it doesn't feed back into the
    // buffer; afterwards adopt the converted text as the new "just typed" run.
    func suspendDuringEdit() { suspended = true }
    func finishEdit(adopting newValue: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.core.adopt(newValue)
            self?.suspended = false
        }
    }

    private func handle(_ event: NSEvent) {
        guard !suspended else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            core.apply(.boundary)                     // caret moved
        case .keyDown:
            if let semantic = Self.semanticEvent(for: event) { core.apply(semantic) }
        default:
            break
        }
    }

    // Translate a key-down into a semantic buffer event, or nil to ignore it.
    static func semanticEvent(for event: NSEvent) -> TypingBufferCore.Event? {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            return .boundary                          // a shortcut, not typing
        }
        switch event.keyCode {
        case 51:                                      // delete / backspace
            return .backspace
        case 36, 76, 48, 53,                          // return, kp-enter, tab, esc
             117, 115, 116, 119, 121,                 // fwd-del, home, pgup, end, pgdn
             123, 124, 125, 126:                      // arrows
            return .boundary
        default:
            // A single keystroke can emit MORE than one character: ArabicPC and
            // Arabic-AZERTY put the mandatory lam-alef ligature لا (U+0644 U+0627,
            // two characters) on the b key. Dropping such keystrokes desynced the
            // buffer from the screen, so the ⇧⇧ fix deleted the wrong span
            // (QA ARABIC-1: "bad" → لاشي → ⇧⇧ → "لاad"). Accept the whole output;
            // the buffer's per-Character backspace stays symmetric with the field.
            guard let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 })
            else { return nil }
            return .printable(chars)                  // the glyph(s) as they appear
        }
    }
}
