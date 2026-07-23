import AppKit

// A snapshot of the whole pasteboard, one entry per item with each item's UTI
// types mapped to their data. Modeling items separately (rather than one flat
// type list) keeps a multi-item clipboard, e.g. several Finder files, intact
// across a save/restore cycle instead of merging it into a single item, and lets
// rich content (images, styled text, URLs) survive too.
struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

enum ClipboardManager {

    private static let pasteboard = NSPasteboard.general

    // Copy-poll cadence: check changeCount this often, up to this many times.
    private static let pollInterval: TimeInterval = 0.005   // 5ms
    private static let maxPollAttempts = 40                 // 40 x 5ms = 200ms

    // MARK: - Save / Restore

    static func save() -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap {
            item -> [NSPasteboard.PasteboardType: Data]? in
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { map[type] = data }
            }
            return map.isEmpty ? nil : map
        }
        return ClipboardSnapshot(items: items)
    }

    static func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { map -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in map { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    // MARK: - Copy current selection

    // Posts Cmd+C, then polls changeCount on pollInterval up to maxPollAttempts.
    // Calls completion with the copied string, or nil on timeout / no selection.
    static func copySelection(completion: @escaping (String?) -> Void) {
        let before = pasteboard.changeCount
        postKey(keyCode: 8, flags: .maskCommand) // 'c'
        poll(before: before, attempt: 0, completion: completion)
    }

    private static func poll(before: Int, attempt: Int, completion: @escaping (String?) -> Void) {
        if pasteboard.changeCount != before {
            completion(pasteboard.string(forType: .string))
            return
        }
        if attempt >= maxPollAttempts {
            completion(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            poll(before: before, attempt: attempt + 1, completion: completion)
        }
    }

    // MARK: - Paste

    // Pastes `text`, fires `onPasted` the instant ⌘V is posted (so the caller can
    // switch layout immediately), then restores the user's clipboard in the
    // background once the target app has consumed the paste, and finally calls
    // `completion`. Splitting these is what makes the fix feel instant: nothing
    // the user perceives waits on the clipboard-restore delay.
    static func paste(_ text: String, onPasted: @escaping () -> Void,
                      thenRestore snapshot: ClipboardSnapshot, completion: @escaping () -> Void) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Hint well-behaved clipboard-history apps (Maccy, Paste, …) to skip
        // this transient value — it's on the pasteboard only long enough to paste.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.006) {
            postKey(keyCode: 9, flags: .maskCommand) // 'v'
            onPasted()
            // Restoring too soon clobbers the pasteboard before the app reads it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                restore(snapshot)
                completion()
            }
        }
    }

    // MARK: - Synthetic key posting

    // Posts a key-down + key-up with the given modifier flags via CGEvent.
    static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
