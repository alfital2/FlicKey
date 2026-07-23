import ApplicationServices
import Foundation
import OSLog

// Fast, clipboard-free text editing via the Accessibility API. Reading the
// selection and replacing it are synchronous IPC calls (single-digit ms) — no
// ⌘C/⌘V round-trips, no pasteboard save/restore, no polling.
//
// NOT every app supports SETTING the selected text (Electron, web content, some
// terminals silently no-op). Callers must treat `replaceSelection` returning
// false as "fall back to the clipboard path". We verify the change actually
// took, so a silent no-op can never corrupt text.
enum AXTextEditor {

    private static let log = Logger(subsystem: "com.talalfi.FlicKey", category: "conversion")

    // The system-wide focused UI element, or nil if there isn't one. Shared by the
    // readers below so both resolve the focused element the same way.
    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            log.notice("AX read: no focused element (err \(focusErr.rawValue, privacy: .public))")
            return nil
        }
        return (focused as! AXUIElement)
    }

    // The focused element and its current selected text, or nil if there's no
    // focused text element / no (non-empty) selection.
    static func selection() -> (element: AXUIElement, text: String)? {
        guard let element = focusedElement() else { return nil }

        var valueRef: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &valueRef)
        guard selErr == .success else {
            log.notice("AX read: no selected-text attribute (err \(selErr.rawValue, privacy: .public))")
            return nil
        }
        guard let text = valueRef as? String, !text.isEmpty else {
            log.notice("AX read: selection empty")
            return nil
        }
        return (element, text)
    }

    // The focused element's characters BEFORE the caret, or nil if the value or
    // caret can't be read. Used to measure the true on-screen length of a run
    // whose keystrokes macOS text services may have expanded (see OnScreenSpan).
    // AX offsets are UTF-16 code units; we map that to a Swift String.Index so the
    // returned characters (graphemes) match the units KeyInput deletes.
    static func focusedTextBeforeCaret() -> [Character]? {
        guard let element = focusedElement() else { return nil }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue((rangeValue as! AXValue), .cfRange, &range) else { return nil }
        let caretUTF16 = range.location + range.length   // insertion point (end of any selection)
        guard caretUTF16 >= 0,
              let u16 = value.utf16.index(value.utf16.startIndex, offsetBy: caretUTF16, limitedBy: value.utf16.endIndex),
              let idx = u16.samePosition(in: value) else { return nil }
        return Array(value[value.startIndex..<idx])
    }

    // Whether the focused element is a SEARCH field, regardless of its content.
    // Auto-switch skips such fields entirely: live-search fields debounce and
    // drop zero-gap synthetic bursts, so an in-place rewrite there garbles text.
    static func focusedElementIsSearchField() -> Bool {
        guard let element = focusedElement() else { return false }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &ref) == .success
        else { return false }
        return (ref as? String) == "AXSearchField"
    }

    // Whether the focused element is a container that holds no editable text — a Finder
    // file list / column browser / outline, a table, etc. Typing there is "type-select"
    // (jump to an item), not text entry, so a synthetic rewrite has nothing to edit and
    // just garbles the type-ahead. Only roles we can positively read as a non-text
    // container return true; an unreadable element (Electron) or any text/unknown role
    // returns false, so the normal fire path is unaffected. Deliberately narrow: it lists
    // only roles that are NEVER text inputs, so it can't stop a real field or a web
    // contenteditable (AXGroup/AXWebArea/AXScrollArea are intentionally excluded).
    static func focusedElementIsNonEditableContainer() -> Bool {
        guard let element = focusedElement() else { return false }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success,
              let role = ref as? String else { return false }
        return nonEditableRoles.contains(role)
    }
    private static let nonEditableRoles: Set<String> = [
        "AXOutline", "AXBrowser", "AXTable", "AXList", "AXRow", "AXCell", "AXColumn",
    ]

    // If the focused element is a SEARCH field (Spotlight, Safari/Chrome toolbar
    // search, etc.), return its current text — else nil. Search fields are
    // special: they append an auto-complete suggestion that AX can't see and that
    // eats the first Backspace, and the keystroke buffer can drift out of sync.
    // The whole field is the query, so the caller replaces it wholesale from THIS
    // value (select-all + type) rather than backspacing the keystroke buffer.
    static func focusedSearchFieldValue() -> String? {
        guard let element = focusedElement() else { return nil }
        func string(_ attr: String) -> String? {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
            return ref as? String
        }
        let role = string(kAXRoleAttribute as String) ?? "?"
        let subrole = string(kAXSubroleAttribute as String) ?? "?"
        guard subrole == "AXSearchField" else {
            log.notice("AX field: role=\(role, privacy: .public) sub=\(subrole, privacy: .public) (not search → backspace path)")
            return nil
        }
        let value = string(kAXValueAttribute as String) ?? ""
        log.notice("AX search field: value.len=\(value.count, privacy: .public)")
        return value.isEmpty ? nil : value
    }

    // Atomically replace the `count` characters immediately before the caret with `text`
    // via the Accessibility API — no synthetic keystrokes, so it CANNOT collide with the
    // user's live typing (that's what lets auto-switch fire instantly instead of waiting
    // for a quiet gap). Selects the run by range, then sets its text. Returns true only if
    // a re-read confirms it took (native text fields); Electron/web/terminals silently
    // no-op → false, so the caller uses the synthetic keystroke path (which needs the pause).
    static func replaceRunBeforeCaret(count: Int, with text: String) -> Bool {
        guard count > 0, let element = focusedElement() else { return false }
        // Only fields that expose SETTABLE selected text can take an atomic replace. Check
        // first, before touching anything: apps that can't (Terminal, Electron, web) must
        // be left completely untouched, or moving the selection below becomes a side effect
        // the synthetic fallback then deletes from the wrong place (the stray-char bug).
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let originalRange = rangeRef, CFGetTypeID(originalRange) == AXValueGetTypeID() else { return false }
        var caret = CFRange()
        guard AXValueGetValue((originalRange as! AXValue), .cfRange, &caret), caret.location >= 0 else { return false }
        let caretU16 = caret.location + caret.length
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String,
              let u16 = value.utf16.index(value.utf16.startIndex, offsetBy: caretU16, limitedBy: value.utf16.endIndex),
              let caretIdx = u16.samePosition(in: value) else { return false }
        let before = value[value.startIndex..<caretIdx]
        guard before.count >= count else { return false }
        let runU16 = String(before.suffix(count)).utf16.count
        guard caretU16 >= runU16 else { return false }
        var sel = CFRange(location: caretU16 - runU16, length: runU16)
        guard let axSel = AXValueCreate(.cfRange, &sel),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axSel) == .success
        else { return false }
        if replaceSelection(element, with: text) { return true }
        // The set no-op'd after we moved the range — put the caret back so a synthetic
        // fallback deletes from the right place. Leaves the field exactly as we found it.
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, originalRange)
        return false
    }

    // Replace the selection with `text`. Returns true ONLY if the set succeeded
    // AND a re-read confirms it took.
    @discardableResult
    static func replaceSelection(_ element: AXUIElement, with text: String) -> Bool {
        let setErr = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard setErr == .success else {
            log.notice("AX set: failed (err \(setErr.rawValue, privacy: .public)) → clipboard")
            return false
        }
        var checkRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &checkRef) == .success,
           let now = checkRef as? String, !(now.isEmpty || now == text) {
            log.notice("AX set: no-op verify failed → clipboard")
            return false
        }
        return true
    }
}
