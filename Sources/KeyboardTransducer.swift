import AppKit
import Carbon
import Foundation

// A physical key, not a character. Retaining this evidence resolves information
// text cannot recover (Arabic b vs g+h, duplicate Armenian keys, Shift vs Caps).
struct KeyboardStroke: Equatable, Hashable {
    let keyCode: UInt16
    var shift = false
    var option = false
    var capsLock = false
}

extension KeyboardStroke {
    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift),
                  option: event.modifierFlags.contains(.option), capsLock: event.modifierFlags.contains(.capsLock))
    }
}

// Immutable, layout-specific input/output machine. macOS owns composition rules;
// we retain its dead-key state while rendering and index composed outputs for
// reverse conversion. No language-specific keyboard tables or network calls.
final class KeyboardTransducer {
    private static let keypadKeys: Set<UInt16> = [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    struct Reading {
        let scalars: [UInt32]
        let strokes: [KeyboardStroke]
        let cost: Int
    }

    private let data: Data?
    private let base: [UInt16: String]
    private let shifted: [UInt16: String]
    private var reverse: [UInt32: [Reading]] = [:]
    private var forward: [KeyboardStroke: String] = [:]

    init(base: [UInt16: String], shift: [UInt16: String]) {
        data = nil
        self.base = base
        shifted = shift
        for (key, text) in base.sorted(by: { $0.key < $1.key }) {
            add(text, strokes: [KeyboardStroke(keyCode: key)])
        }
        for (key, text) in shift.sorted(by: { $0.key < $1.key }) {
            add(text, strokes: [KeyboardStroke(keyCode: key, shift: true)])
        }
        finishIndex()
    }

    init(data: Data) {
        self.data = data
        base = [:]
        shifted = [:]
        // Main keyboard, ISO extra key, and JIS printable keys. Keypad duplicates
        // must not win inverse lookup over the main keyboard's punctuation.
        let keys = Array(UInt16(0)...50).filter { ![36, 48].contains($0) }
            + Self.keypadKeys.sorted() + [93, 94, 95, 102]
        var dead: [KeyboardStroke] = []
        let strokes = [false, true].flatMap { option in
            [false, true].flatMap { shift in
                keys.map { KeyboardStroke(keyCode: $0, shift: shift, option: option) }
            }
        }
        for stroke in strokes {
            var state: UInt32 = 0
            let plain = translate(stroke, state: &state, noDeadKeys: true)
            if let plain, Self.printable(plain) { add(plain, strokes: [stroke]) }
            state = 0
            if let text = translate(stroke, state: &state), text.isEmpty, state != 0 {
                dead.append(stroke)
            }
        }
        for prefix in dead {
            for stroke in strokes {
                var state: UInt32 = 0
                _ = translate(prefix, state: &state)
                guard let text = translate(stroke, state: &state), Self.printable(text) else { continue }
                // Only actual composition. An unsupported combination emits a
                // spacing accent followed by the second key and is already
                // representable by the ordinary paths.
                guard text.count == 1 else { continue }
                add(text, strokes: [prefix, stroke])
            }
        }
        finishIndex()
    }

    private static func printable(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            $0.properties.generalCategory != .control
        }
    }

    private func add(_ text: String, strokes: [KeyboardStroke]) {
        if strokes.count == 1 { forward[strokes[0]] = text }
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
        guard let first = scalars.first else { return }
        // Prefer ordinary keys, then Shift, then Option, then composed sequences.
        // Prefer the main keyboard over JIS-only alternatives. An unshifted
        // character on a JIS key must not displace a normal Shift+number reading
        // (e.g. Russian '*'), or land on an unassigned key in the target layout.
        let cost = strokes.reduce(0) {
            $0 + (Self.keypadKeys.contains($1.keyCode) ? 10 : ($1.keyCode > 50 ? 100 : 0))
                + ($1.option ? 20 : 0) + ($1.shift ? 1 : 0)
        }
            + (strokes.count - 1) * 2
        let reading = Reading(scalars: scalars, strokes: strokes, cost: cost)
        var entries = reverse[first, default: []]
        // Shift/Option producing the same text on the same key carries no extra
        // recoverable evidence. Recorded physical strokes still preserve it.
        if entries.contains(where: {
            $0.scalars == scalars && $0.strokes.map(\.keyCode) == strokes.map(\.keyCode)
                && $0.cost <= cost
        }) { return }
        entries.append(reading)
        reverse[first] = entries
    }

    private func finishIndex() {
        for key in Array(reverse.keys) {
            reverse[key]?.sort {
                if $0.scalars.count != $1.scalars.count { return $0.scalars.count < $1.scalars.count }
                if $0.cost != $1.cost { return $0.cost < $1.cost }
                return $0.strokes.map(\.keyCode).lexicographicallyPrecedes($1.strokes.map(\.keyCode))
            }
        }
    }

    func readings(in scalars: [UInt32], at index: Int) -> [Reading] {
        (reverse[scalars[index]] ?? []).filter { reading in
            let end = index + reading.scalars.count
            guard end <= scalars.count && scalars[index..<end].elementsEqual(reading.scalars) else { return false }
            // Option supplies real letters/accents, but also currency and
            // typography shared between languages. Text alone is not evidence
            // that a user's € or em dash was a wrong-layout Option chord.
            return !reading.strokes.contains(where: \.option) || reading.scalars.allSatisfy {
                guard let scalar = Unicode.Scalar($0) else { return false }
                return CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar)
            }
        }
    }

    func isDeadKey(_ stroke: KeyboardStroke) -> Bool {
        var state: UInt32 = 0
        return translate(stroke, state: &state)?.isEmpty == true && state != 0
    }

    func standalone(_ stroke: KeyboardStroke) -> String? {
        if stroke.keyCode == 49 { return " " }
        if let result = forward[stroke], !stroke.capsLock { return result }
        if data != nil {
            var state: UInt32 = 0
            return translate(stroke, state: &state, noDeadKeys: true)
        }
        let shiftedPlane = stroke.shift != stroke.capsLock
        return shiftedPlane ? shifted[stroke.keyCode] : base[stroke.keyCode]
    }

    // Spaces flush pending accents in the same way actual keyboard input does.
    // Strip only the extra flush-space, retaining an unfinished spacing accent.
    func render(_ strokes: [KeyboardStroke]) -> String? {
        rendering(strokes, finish: true)?.text
    }

    // Candidate prefixes with identical visible text can still hold different
    // pending accents. Keep the composition state in their deduplication key.
    func prefixIdentity(_ strokes: [KeyboardStroke]) -> String? {
        guard let result = rendering(strokes, finish: false) else { return nil }
        return result.text + "\u{0}" + String(result.state)
    }

    private func rendering(_ strokes: [KeyboardStroke], finish: Bool) -> (text: String, state: UInt32)? {
        var result = "", state: UInt32 = 0
        for stroke in strokes {
            if data == nil {
                guard let text = standalone(stroke) else { return nil }
                result += text
            } else {
                // A dead key or an unassigned modifier plane can legitimately
                // emit nothing. Format scalars (Persian ZWNJ, joiners, bidi
                // marks) are also text, not control-key commands.
                guard let text = translate(stroke, state: &state),
                      text.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control })
                else { return nil }
                result += text
            }
        }
        if finish, data != nil, state != 0 {
            if var tail = translate(KeyboardStroke(keyCode: 49), state: &state) {
                if tail.hasSuffix(" ") { tail.removeLast() }
                result += tail
            }
        }
        return (result.precomposedStringWithCanonicalMapping, state)
    }

    private func translate(_ stroke: KeyboardStroke, state: inout UInt32,
                           noDeadKeys: Bool = false) -> String? {
        guard let data else { return nil }
        return data.withUnsafeBytes { buffer in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var chars = [UniChar](repeating: 0, count: 32), length = 0
            let modifiers: UInt32 = (stroke.shift ? 2 : 0) | (stroke.capsLock ? 4 : 0) | (stroke.option ? 8 : 0)
            let status = UCKeyTranslate(layout, stroke.keyCode, UInt16(kUCKeyActionDown), modifiers,
                                        UInt32(LMGetKbdType()), noDeadKeys ? UInt32(kUCKeyTranslateNoDeadKeysMask) : 0,
                                        &state, chars.count, &length, &chars)
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : nil
        }
    }
}

// Bounded, in-memory evidence for the contiguous typing run only. Any edit we
// cannot account for invalidates it. Before use, rendering must match the exact
// text being converted; stale traces can never override newer text.
struct LayoutTypingTrace {
    private(set) var strokes: [KeyboardStroke] = []
    private(set) var sourceID: String?

    mutating func append(_ stroke: KeyboardStroke, sourceID: String?) {
        guard let sourceID else { reset(); return }
        if self.sourceID != sourceID { reset(); self.sourceID = sourceID }
        guard strokes.count < 256 else { reset(); return }
        strokes.append(stroke)
    }

    func verified(for text: String, map: LayoutMap?) -> [KeyboardStroke]? {
        guard !text.isEmpty, !strokes.isEmpty, let map, sourceID == map.sourceID,
              map.transducer.render(strokes) == text else { return nil }
        return strokes
    }

    mutating func keepSuffix(_ text: String, map: LayoutMap?) {
        guard !text.isEmpty, let map, sourceID == map.sourceID else { reset(); return }
        for start in strokes.indices {
            let suffix = Array(strokes[start...])
            if map.transducer.render(suffix) == text { strokes = suffix; return }
        }
        reset()
    }

    mutating func reset() { strokes = []; sourceID = nil }

    mutating func adopt(_ text: String, map: LayoutMap?) {
        guard let map, !strokes.isEmpty, map.transducer.render(strokes) == text else { reset(); return }
        sourceID = map.sourceID
    }
}
