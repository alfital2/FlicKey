import Foundation

// Pure decision layer for the instant-conversion "replace" path, split out of
// HotkeyManager's live AX / event-posting machinery so it can be unit-tested.
// Given what the user just typed — and, when the focused field is a SEARCH field,
// that field's actual text — it decides HOW to replace and converts the correct
// source text.
enum ReplacePlan: Equatable {
    // Search fields (Spotlight, browser toolbar search) hide an auto-complete
    // suggestion that Accessibility can't see and that eats the first Backspace.
    // The whole field is the query, so the executor does select-all + type this
    // converted text — no backspaces (which is exactly what the off-by-one needed).
    case searchReplace(text: String, sourceID: String?)
    // Plain fields: delete the `count` characters the user typed, then type the
    // converted text in place.
    case backspaceReplace(count: Int, text: String, sourceID: String?)
}

enum ConversionRouter {

    // Prefer the generic layout converter; fall back to the built-in en↔he
    // tables if a layout pair can't be derived. Folds smart-quote variants to
    // ASCII first so BOTH paths see the apostrophe the layout map knows.
    static func convertText(_ rawText: String) -> (converted: String, sourceID: String?) {
        let text = ConversionEngine.normalizeQuotes(rawText)
        if let result = LayoutConverter.convert(text) {
            return (result.converted, result.targetSourceID)
        }
        let (converted, target) = ConversionEngine.convert(text)
        return (converted, InputSourceManager.langToSource[target])
    }

    // Decide how to replace. `searchFieldValue` is the focused field's text IFF it
    // is a search field (else nil). Search fields convert the FIELD's text and
    // replace it wholesale; plain fields convert and backspace the keystroke
    // buffer. Returns nil when there's nothing to convert.
    static func replacePlan(typed: String, searchFieldValue: String?) -> ReplacePlan? {
        guard !typed.isEmpty else { return nil }
        if let value = searchFieldValue, !value.isEmpty {
            let r = convertText(value)
            return .searchReplace(text: r.converted, sourceID: r.sourceID)
        }
        let r = convertText(typed)
        return .backspaceReplace(count: typed.count, text: r.converted, sourceID: r.sourceID)
    }
}
