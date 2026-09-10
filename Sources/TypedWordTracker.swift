import AppKit

enum KeyStroke: Equatable {
    case letter(Character)
    case space       // soft word separator — emits the word, the run continues
    case hardBreak   // return/tab/nav/punctuation — emits the word, the run ends
    case backspace
}

// What ended a typing run; carried on onRegionBreak so diagnostics can say
// WHY a wrong-layout streak died (Enter, a click, a shortcut, an app switch).
enum RegionBreakKind: String, Codable, Equatable {
    case key         // return/tab/nav/non-layout punctuation
    case click
    case shortcut    // ⌘/⌃ chord
    case appSwitch
}

// Pure state machine: letters accumulate, a separator emits + clears the word.
// `.space` and `.hardBreak` both end a word; the tracker uses the distinction to
// decide whether the wrong-layout run continues (space) or ends (hard break).
//
// `run` is a byte-accurate mirror of the on-screen text since the run last
// started: letters and soft spaces append, backspace removes one, a hard break
// clears it. Auto-switch reconstructs a wrong-layout passage from it. The
// in-progress word is DERIVED from the run (its tail after the last space), so
// the two can never diverge: backspacing across a word boundary rejoins the
// previous word instead of leaving a phantom empty word. A run starts fresh on
// `resetRun()`, which the caller uses to drop already-committed (correctly
// typed) words so only the current wrong streak is reconstructed.
struct WordAccumulator {
    private(set) var run = ""
    private let maxLength = 120

    // The in-progress word: everything after the run's last space.
    var current: String {
        if let idx = run.lastIndex(of: " ") { return String(run[run.index(after: idx)...]) }
        return run
    }

    mutating func feed(_ k: KeyStroke) -> String? {
        switch k {
        case .letter(let c):
            run.append(c)
            if run.count > maxLength { run.removeFirst(run.count - maxLength) }
            return nil
        case .backspace:
            if !run.isEmpty { run.removeLast() }
            return nil
        case .space:
            let word = current
            run.append(" ")
            return word.isEmpty ? nil : word
        case .hardBreak:
            let word = current
            run = ""
            return word.isEmpty ? nil : word
        }
    }

    mutating func reset() { run = "" }
    // Drop committed text from the run; `keeping` restarts it with a suffix that
    // is still part of the new streak (a word whose target disagreed with the
    // words before it starts a fresh streak that includes itself).
    mutating func resetRun(keeping suffix: String = "") { run = suffix }
}

// Global + local keystroke monitor (same pattern as TypingBuffer) that turns
// NSEvents into KeyStrokes and reports completed words. Global monitor covers
// other apps; local covers FlicKey's own fields.
final class TypedWordTracker {

    // A completed word plus whether a soft space ended it (vs a hard break). Only
    // a soft-space completion can continue a wrong-layout run.
    var onWordCompleted: ((_ word: String, _ endedBySpace: Bool) -> Void)?
    // A hard boundary that ends the current run, with what caused it — fires
    // AFTER any word the same event completed.
    var onRegionBreak: ((RegionBreakKind) -> Void)?
    // Any real typing keystroke (letter, space, backspace, hard break), with
    // whether it was a backspace. Lets a consumer notice the user typed on (to
    // invalidate a pending undo) or is editing (to disarm a pending fire).
    var onInput: ((_ isBackspace: Bool) -> Void)?

    // Byte-accurate on-screen text of the current wrong-layout streak.
    var currentRun: String { accumulator.run }
    // Drop already-committed (correctly-typed) text so the next reconstruction
    // starts at the current streak; `keeping` seeds it with a suffix that still
    // belongs to the new streak.
    func resetRun(keeping suffix: String = "") { accumulator.resetRun(keeping: suffix) }

    // While a synthetic backspace/retype is in flight, ignore events so the
    // rewrite doesn't feed back as typing. endSyntheticEdit clears the buffer so
    // the converted text left behind isn't mistaken for a new run.
    private var suspended = false
    func beginSyntheticEdit() { suspended = true }
    func endSyntheticEdit() { accumulator.reset(); suspended = false }

    private var accumulator = WordAccumulator()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private static let watched: NSEvent.EventTypeMask =
        [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    // Returns whether the global keyboard monitor is live. Each component is
    // installed independently so a failed global monitor can be retried without
    // duplicating the local monitor or workspace observer.
    @discardableResult
    func start() -> Bool {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.watched) {
                [weak self] event in self?.handle(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.watched) {
                [weak self] event in self?.handle(event); return event
            }
        }
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.accumulator.reset(); self?.onRegionBreak?(.appSwitch) }
        }
        return globalMonitor != nil
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard !suspended else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // A click moves the caret: discard the in-progress word and end the run.
            accumulator.reset()
            onRegionBreak?(.click)
        case .keyDown:
            // A ⌘/⌃ chord is a shortcut, not typing — discard the word and end the
            // run (else the app's own ⇧⇧ fix, whose search path posts ⌘A, would
            // spuriously complete a word mid-correction).
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                accumulator.reset()
                onRegionBreak?(.shortcut)
                return
            }
            guard let strokes = Self.strokes(for: event), !strokes.isEmpty else { return }
            onInput?(strokes == [.backspace])
            for stroke in strokes {
                let endedBySpace = (stroke == .space)
                if let word = accumulator.feed(stroke) { onWordCompleted?(word, endedBySpace) }
                if case .hardBreak = stroke { onRegionBreak?(.key) }
            }
        default:
            break
        }
    }

    // Punctuation keys that produce a LETTER on some supported keyboard layout,
    // so they belong inside a wrong-layout word rather than ending it. Verified
    // against the real layouts (UCKeyTranslate): Hebrew puts ת ץ ף on , . ; and a
    // geresh on w (as ' on the PC layout, ׳ U+05F3 / ’ U+2019 on the others);
    // Russian puts б ю ж э х ъ ё on , . ; ' [ ] \; Ukrainian adds ї on ] and ґ/ʼ
    // on ` and \; Arabic puts و ز ك ط on letter keys and ، ؛ on , and '.
    static let layoutPunctuation: Set<Character> = [
        ",", ".", ";", "'", "/", "`", "[", "]", "\\",
        "\u{05F3}", "\u{2019}",   // Hebrew geresh forms (Hebrew, Hebrew-QWERTY)
        "\u{060C}", "\u{061B}",   // Arabic comma / semicolon (letter-adjacent keys)
    ]

    // Classifies a single printable typed character into a KeyStroke.
    static func stroke(forCharacter ch: Character) -> KeyStroke {
        if ch == " " { return .space }
        if ch.isLetter || layoutPunctuation.contains(ch) { return .letter(ch) }
        return .hardBreak                          // other punctuation / digits end the run
    }

    // Classifies a key's full text output. A single key can emit more than one
    // character (ArabicPC's b key produces لا); dropping such output would desync
    // the run from the screen, so a multi-character output of word characters
    // feeds each one. Anything mixed ends the run rather than guessing.
    static func strokes(forOutput chars: String) -> [KeyStroke] {
        if chars.count == 1, let ch = chars.first { return [stroke(forCharacter: ch)] }
        let strokes = chars.map { stroke(forCharacter: $0) }
        let allWordChars = strokes.allSatisfy { if case .letter = $0 { return true }; return false }
        return allWordChars ? strokes : [.hardBreak]
    }

    // Maps a keyDown to KeyStrokes. Only space continues a wrong-layout run;
    // most punctuation, digits, and navigation keys end it.
    private static func strokes(for event: NSEvent) -> [KeyStroke]? {
        switch event.keyCode {
        case 51:                                   // backspace
            return [.backspace]
        case 36, 76, 48, 53,                       // return, kp-enter, tab, esc
             117, 115, 116, 119, 121,              // fwd-del, home, pgup, end, pgdn
             123, 124, 125, 126:                   // arrows
            return [.hardBreak]
        default:
            guard let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 })
            else { return nil }
            return strokes(forOutput: chars)
        }
    }
}
