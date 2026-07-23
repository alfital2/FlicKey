import Carbon
import Foundation

// A keyboard input source the user has enabled in System Settings.
struct InputSourceInfo: Equatable {
    let id: String              // e.g. "com.apple.keylayout.Hebrew-PC"
    let localizedName: String   // e.g. "Hebrew – PC"
    let languageCodes: [String] // e.g. ["he", "yi"]

    var primaryCode: String {
        guard let code = languageCodes.first, !code.isEmpty else { return "?" }
        return String(code.prefix(2)).uppercased()
    }
}

// Reads the user's enabled keyboard layouts straight from macOS (Carbon TIS),
// so the app generalizes to whatever languages they've added — no hard-coding.
enum InputSourceCatalog {

    static func enabledSources() -> [InputSourceInfo] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
            as? [TISInputSource] else { return [] }

        return list.compactMap { source in
            guard string(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String),
                  bool(source, kTISPropertyInputSourceIsSelectCapable),
                  let id = string(source, kTISPropertyInputSourceID),
                  let name = string(source, kTISPropertyLocalizedName)
            else { return nil }
            return InputSourceInfo(id: id, localizedName: name,
                                   languageCodes: strings(source, kTISPropertyInputSourceLanguages))
        }
    }

    static func localizedName(for id: String) -> String? {
        enabledSources().first { $0.id == id }?.localizedName
    }

    // MARK: - Property helpers

    // Reads a CFString-valued TIS property. Internal so InputSourceManager can read
    // the input-source ID through the same helper instead of copying it.
    static func string(_ s: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(s, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func bool(_ s: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(s, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    private static func strings(_ s: TISInputSource, _ key: CFString) -> [String] {
        guard let ptr = TISGetInputSourceProperty(s, key),
              let array = (Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as NSArray) as? [String]
        else { return [] }
        return array
    }
}
