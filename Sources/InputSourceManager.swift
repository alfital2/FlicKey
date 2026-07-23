import Foundation
import Carbon

// Reads and switches the active macOS keyboard input source via the Carbon
// Text Input Sources (TIS) API.
enum InputSourceManager {

    // Maps a language to its macOS input source ID.
    // Verified enabled on this machine via TISCreateInputSourceList.
    // To find IDs on another machine, enumerate TISCreateInputSourceList and
    // read kTISPropertyInputSourceID.
    static let langToSource: [Language: String] = [
        .en: "com.apple.keylayout.ABC",
        .he: "com.apple.keylayout.Hebrew-PC",
    ]

    // A short uppercase language code for the active input source ("EN", "HE",
    // "FR"…), read from macOS's own metadata for the source. "?" if unknown.
    static func currentSourceCode() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let langs = (Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as NSArray) as? [String],
              let code = langs.first, !code.isEmpty
        else { return "?" }
        return String(code.prefix(2)).uppercased()
    }

    // The currently active keyboard input source ID, e.g. "com.apple.keylayout.ABC".
    static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return InputSourceCatalog.string(source, kTISPropertyInputSourceID)
    }

    static func switchTo(sourceID: String) {
        guard currentSourceID() != sourceID else { return } // already current

        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
            as? [TISInputSource] else { return }

        for source in list
        where InputSourceCatalog.string(source, kTISPropertyInputSourceID) == sourceID {
            TISSelectInputSource(source)
            return
        }
    }
}
