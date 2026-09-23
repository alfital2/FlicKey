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

    private static let validator = WrongLayoutClassifier(spellChecker: SystemSpellChecker(),
                                                         candidates: { _ in [] })

    static func convertText(_ rawText: String, physicalStrokes: [KeyboardStroke]? = nil)
        -> (converted: String, sourceID: String?) {
        convertText(rawText, maps: LayoutConverter.enabledMaps(),
                    currentSourceID: InputSourceManager.currentSourceID(), physicalStrokes: physicalStrokes,
                    preferring: { validator.validatesAsRealWord($0) })
    }

    // Unsupported input methods must never fall through to the old EN↔HE
    // converter. A known physical source is required before touching text.
    static func convertText(_ rawText: String, maps: [LayoutMap], currentSourceID: String?,
                            physicalStrokes: [KeyboardStroke]? = nil,
                            preferring isRealWord: (String) -> Bool = { _ in false })
        -> (converted: String, sourceID: String?) {
        guard maps.count >= 2,
              let sourceIndex = maps.firstIndex(where: { $0.sourceID == currentSourceID })
        else { return (rawText, nil) }
        let target = maps[(sourceIndex + 1) % maps.count]
        if let physicalStrokes,
           let converted = LayoutConverter.convertCaptured(rawText, strokes: physicalStrokes,
                                                           from: maps[sourceIndex], to: target,
                                                           applyingCorrectionPolicy: true) {
            return (converted, target.sourceID)
        }
        let text = ConversionEngine.normalizeQuotes(rawText)
        guard let initial = LayoutConverter.convert(text, maps: maps, currentSourceID: currentSourceID),
              let id = initial.targetSourceID,
              let result = LayoutConverter.convert(text, toSourceID: id, maps: maps,
                                                   currentSourceID: currentSourceID, preferring: isRealWord)
        else { return (rawText, nil) }
        return (result.converted, result.targetSourceID)
    }

    // Decide how to replace. `searchFieldValue` is the focused field's text IFF it
    // is a search field (else nil). Search fields convert the FIELD's text and
    // replace it wholesale; plain fields convert and backspace the keystroke
    // buffer. Returns nil when there's nothing to convert.
    static func replacePlan(typed: String, searchFieldValue: String?,
                            physicalStrokes: [KeyboardStroke]? = nil) -> ReplacePlan? {
        guard !typed.isEmpty else { return nil }
        if let value = searchFieldValue, !value.isEmpty {
            let r = convertText(value, physicalStrokes: value == typed ? physicalStrokes : nil)
            guard r.sourceID != nil else { return nil }
            return .searchReplace(text: r.converted, sourceID: r.sourceID)
        }
        let r = convertText(typed, physicalStrokes: physicalStrokes)
        guard r.sourceID != nil else { return nil }
        return .backspaceReplace(count: typed.count, text: r.converted, sourceID: r.sourceID)
    }
}
