import Carbon
import Foundation

// Derives a keyboard layout's physical-key ↔ character mapping straight from
// macOS (UCKeyTranslate on the layout's uchr data), so layout conversion is
// generic for any installed layout — no hard-coded tables.
struct LayoutMap {

    let sourceID: String
    private let keyToChar: [UInt16: String]        // unshifted
    private let keyToCharShift: [UInt16: String]   // shifted
    private let charToKey: [String: (key: UInt16, shift: Bool)]
    let producedCharacters: Set<String>
    // The longest string any single key produces, in Characters. Almost always 1;
    // ArabicPC/Arabic-AZERTY produce the two-character lam-alef لا from the b key.
    // The converter uses this for its longest-match-first walk, so such digraphs
    // map back to their physical key instead of being split per character.
    let maxProducedLength: Int

    private static var cache: [String: LayoutMap] = [:]

    static func forSource(_ id: String) -> LayoutMap? {
        if let cached = cache[id] { return cached }
        guard let map = LayoutMap(sourceID: id) else { return nil }
        cache[id] = map
        return map
    }

    init?(sourceID: String) {
        guard let data = Self.layoutData(forID: sourceID) else { return nil }

        var normal: [UInt16: String] = [:]
        var shifted: [UInt16: String] = [:]
        var reverse: [String: (UInt16, Bool)] = [:]
        var produced = Set<String>()

        for keyCode in UInt16(0)...127 {
            if let c = Self.translate(data, keyCode, shift: false) {
                normal[keyCode] = c
                produced.insert(c)
                if reverse[c] == nil { reverse[c] = (keyCode, false) }
            }
            if let c = Self.translate(data, keyCode, shift: true) {
                shifted[keyCode] = c
                produced.insert(c)
                if reverse[c] == nil { reverse[c] = (keyCode, true) }
            }
        }
        guard !produced.isEmpty else { return nil }

        self.sourceID = sourceID
        self.keyToChar = normal
        self.keyToCharShift = shifted
        self.charToKey = reverse
        self.producedCharacters = produced
        self.maxProducedLength = produced.map(\.count).max() ?? 1
    }

    // Fixture initializer for tests: build a map from explicit key→character
    // tables instead of querying macOS, so converter tests run anywhere without
    // the layouts installed.
    init(sourceID: String, keyToChar: [UInt16: String], keyToCharShift: [UInt16: String] = [:]) {
        var reverse: [String: (UInt16, Bool)] = [:]
        var produced = Set<String>()
        for (key, char) in keyToChar.sorted(by: { $0.key < $1.key }) {
            produced.insert(char)
            if reverse[char] == nil { reverse[char] = (key, false) }
        }
        for (key, char) in keyToCharShift.sorted(by: { $0.key < $1.key }) {
            produced.insert(char)
            if reverse[char] == nil { reverse[char] = (key, true) }
        }
        self.sourceID = sourceID
        self.keyToChar = keyToChar
        self.keyToCharShift = keyToCharShift
        self.charToKey = reverse
        self.producedCharacters = produced
        self.maxProducedLength = produced.map(\.count).max() ?? 1
    }

    func character(forKeyCode keyCode: UInt16, shift: Bool) -> String? {
        shift ? keyToCharShift[keyCode] : keyToChar[keyCode]
    }

    func key(forCharacter character: String) -> (key: UInt16, shift: Bool)? {
        charToKey[character]
    }

    // MARK: - UCKeyTranslate

    private static func layoutData(forID id: String) -> Data? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
            as? [TISInputSource] else { return nil }
        for source in list {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  (Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String) == id,
                  let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { continue }
            return Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        }
        return nil
    }

    private static func translate(_ data: Data, _ keyCode: UInt16, shift: Bool) -> String? {
        data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            let modifiers: UInt32 = shift ? 2 : 0 // (shiftKey >> 8) & 0xFF
            let err = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers,
                                     UInt32(LMGetKbdType()),
                                     OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                     &deadKeyState, chars.count, &length, &chars)
            guard err == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: chars, count: length)
            // Skip control characters (return, tab, space, escape…).
            guard string.unicodeScalars.allSatisfy({ $0.value > 0x20 }) else { return nil }
            return string
        }
    }
}
