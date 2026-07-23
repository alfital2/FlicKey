import Foundation

// Generic wrong-layout text fixer. Converts text to the NEXT enabled keyboard
// layout in a cycle, using maps derived live from macOS (LayoutMap) — no
// hard-coded tables. With two layouts this is the classic "switch to the other
// one"; with three or more, repeated invocations (re-selecting the result) walk
// through every layout and back to the original. Each conversion also switches
// the system layout, so the next press detects the new source automatically.
enum LayoutConverter {

    // The enabled keyboard layouts, in order, as maps.
    static func enabledMaps() -> [LayoutMap] {
        InputSourceCatalog.enabledSources().compactMap { LayoutMap.forSource($0.id) }
    }

    // Returns the converted text and the input source to switch to. The outer
    // optional is nil only when no usable layout set is available.
    //
    // Direction: when the text has characters exclusive to one layout, that's the
    // source. When it doesn't (pure punctuation/digits — ambiguous), the CURRENT
    // input source is the source, so punctuation round-trips correctly (e.g.
    // w→' then '→w) instead of cascading.
    static func convert(_ text: String) -> (converted: String, targetSourceID: String?)? {
        convert(text, currentSourceID: InputSourceManager.currentSourceID())
    }

    static func convert(_ text: String, currentSourceID: String?)
        -> (converted: String, targetSourceID: String?)? {
        convert(text, maps: enabledMaps(), currentSourceID: currentSourceID)
    }

    // Two-layout convenience, kept for tests; delegates to the N-layout core.
    static func convert(_ text: String, between a: LayoutMap, and b: LayoutMap,
                        currentSourceID: String?) -> (converted: String, targetSourceID: String?) {
        convert(text, maps: [a, b], currentSourceID: currentSourceID) ?? (text, nil)
    }

    // N-layout core: find the layout the text is in, convert to the next in the
    // cycle. Pure — fixture layouts make it fully testable.
    static func convert(_ text: String, maps: [LayoutMap], currentSourceID: String?)
        -> (converted: String, targetSourceID: String?)? {
        guard maps.count >= 2 else { return nil }
        guard let sourceIndex = sourceIndex(of: text, in: maps, currentSourceID: currentSourceID) else {
            return (text, nil) // ambiguous and current layout isn't in the set
        }
        let target = maps[(sourceIndex + 1) % maps.count]
        return (convert(text, from: maps[sourceIndex], to: target), target.sourceID)
    }

    // Every other-layout reading of `text`: the conversion from its detected
    // source layout to EACH other enabled layout, in layout order. Auto-switch
    // asks a dictionary which of these is a real word, so with three or more
    // layouts the fix goes to the layout that validates, not just next-in-cycle.
    static func candidates(_ text: String) -> [(converted: String, targetSourceID: String?)] {
        candidates(text, maps: enabledMaps(), currentSourceID: InputSourceManager.currentSourceID())
    }

    static func candidates(_ text: String, maps: [LayoutMap], currentSourceID: String?)
        -> [(converted: String, targetSourceID: String?)] {
        guard maps.count >= 2,
              let sourceIndex = sourceIndex(of: text, in: maps, currentSourceID: currentSourceID)
        else { return [] }
        return maps.indices.flatMap { index -> [(String, String?)] in
            guard index != sourceIndex else { return [] }
            // Every plausible reading (per-character + digraph-greedy when the
            // source has multi-character keys) — the classifier's dictionary picks
            // the real word, so "لاشي" resolves to "bad" even though the
            // per-character reading is "ghad".
            return parses(of: text, from: maps[sourceIndex], to: maps[index])
                .map { ($0, maps[index].sourceID) }
        }
    }

    // Convert to one specific enabled layout (nil if it isn't enabled, or the
    // text is already in it).
    static func convert(_ text: String, toSourceID id: String)
        -> (converted: String, targetSourceID: String?)? {
        convert(text, toSourceID: id, maps: enabledMaps(),
                currentSourceID: InputSourceManager.currentSourceID())
    }

    static func convert(_ text: String, toSourceID id: String, maps: [LayoutMap],
                        currentSourceID: String?) -> (converted: String, targetSourceID: String?)? {
        guard let target = maps.first(where: { $0.sourceID == id }),
              let sourceIndex = sourceIndex(of: text, in: maps, currentSourceID: currentSourceID),
              maps[sourceIndex].sourceID != id
        else { return nil }
        return (convert(text, from: maps[sourceIndex], to: target), id)
    }

    // Convert to one specific layout, choosing among the plausible readings with
    // the caller's validator (word-count of dictionary-valid words). Falls back to
    // the per-character reading on a tie, preserving today's behavior everywhere a
    // digraph isn't involved.
    static func convert(_ text: String, toSourceID id: String,
                        preferring isRealWord: (String) -> Bool)
        -> (converted: String, targetSourceID: String?)? {
        convert(text, toSourceID: id, maps: enabledMaps(),
                currentSourceID: InputSourceManager.currentSourceID(), preferring: isRealWord)
    }

    static func convert(_ text: String, toSourceID id: String, maps: [LayoutMap],
                        currentSourceID: String?, preferring isRealWord: (String) -> Bool)
        -> (converted: String, targetSourceID: String?)? {
        guard let target = maps.first(where: { $0.sourceID == id }),
              let sourceIndex = sourceIndex(of: text, in: maps, currentSourceID: currentSourceID),
              maps[sourceIndex].sourceID != id
        else { return nil }
        let options = parses(of: text, from: maps[sourceIndex], to: target)
        guard options.count > 1 else { return (options[0], id) }
        func score(_ s: String) -> Int {
            s.split(separator: " ").filter { isRealWord(String($0)) }.count
        }
        let best = options.dropFirst().reduce(options[0]) { current, challenger in
            score(challenger) > score(current) ? challenger : current
        }
        return (best, id)
    }

    // Per-character conversion between two concrete layouts. NOTE: a single key
    // can produce a multi-character string (ArabicPC's b → لا), which this walk
    // cannot match backwards — and must not match greedily either, because the
    // same character pair also arises from separate keys (ل=g + ا=h), so a greedy
    // parse would corrupt every English word containing "gh" (high, night…). The
    // ambiguity is resolved where a dictionary is available: `parses(of:)` below
    // returns BOTH readings and auto-switch validates which one is a real word.
    private static func convert(_ text: String, from source: LayoutMap, to target: LayoutMap) -> String {
        var result = ""
        for character in text {
            let s = String(character)
            guard let key = source.key(forCharacter: s) else { result += s; continue }
            if character.isUppercase {
                // Map uppercase letters by their PHYSICAL key to the target's base
                // (unshifted) letter, then re-apply case. uppercased() yields a
                // real capital in cased scripts (Cyrillic/Greek) and a no-op in
                // case-less ones (Hebrew/Arabic). This avoids the target's shifted
                // plane, which can echo Latin (Hebrew shift+key → "A") and break
                // the conversion.
                if let base = target.character(forKeyCode: key.key, shift: false) {
                    result += base.uppercased()
                } else if let same = target.character(forKeyCode: key.key, shift: true) {
                    result += same
                } else {
                    result += s
                }
            } else if let mapped = target.character(forKeyCode: key.key, shift: key.shift) {
                result += mapped
            } else {
                result += s
            }
        }
        return result
    }

    // All plausible readings of `text` converted from `source` to `target`: the
    // per-character parse first, and — when the source layout has multi-character
    // keys (ArabicPC/Arabic-AZERTY: b → لا) — the digraph-greedy parse as well, if
    // it differs. The caller disambiguates: auto-switch checks each against a
    // dictionary, so "لاشي" offers both "ghad" and "bad" and the real word wins.
    static func parses(of text: String, from source: LayoutMap, to target: LayoutMap) -> [String] {
        let perCharacter = convert(text, from: source, to: target)
        guard source.maxProducedLength > 1 else { return [perCharacter] }
        let greedy = greedyConvert(text, from: source, to: target)
        return greedy == perCharacter ? [perCharacter] : [perCharacter, greedy]
    }

    // The digraph-greedy walk: at each position the longest produced chunk (≥ 2
    // characters) maps by its physical key; everything else per-character.
    private static func greedyConvert(_ text: String, from source: LayoutMap, to target: LayoutMap) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if let (chunkEnd, key) = longestChunk(in: text, at: index, from: source),
               let mapped = target.character(forKeyCode: key.key, shift: key.shift) {
                result += mapped
                index = chunkEnd
                continue
            }
            let end = text.index(after: index)
            result += convert(String(text[index..<end]), from: source, to: target)
            index = end
        }
        return result
    }

    // The longest multi-character chunk at `index` that some single source key
    // produces (length ≥ 2), with its key. nil when only single-character (or no)
    // matches exist there — the caller then takes the per-character path.
    private static func longestChunk(in text: String, at index: String.Index, from source: LayoutMap)
        -> (end: String.Index, key: (key: UInt16, shift: Bool))? {
        var length = min(source.maxProducedLength, text.distance(from: index, to: text.endIndex))
        while length >= 2 {
            let end = text.index(index, offsetBy: length)
            if let key = source.key(forCharacter: String(text[index..<end])) {
                return (end, key)
            }
            length -= 1
        }
        return nil
    }

    // The layout the text was (mistakenly) typed in: the one with the most
    // characters exclusive to it. Ties / none (pure punctuation, or near-identical
    // layouts like RU+UA that share most letters) → the current layout.
    private static func sourceIndex(of text: String, in maps: [LayoutMap],
                                    currentSourceID: String?) -> Int? {
        var scores = [Int](repeating: 0, count: maps.count)
        for character in text {
            let s = String(character)
            let producers = maps.indices.filter { maps[$0].producedCharacters.contains(s) }
            if producers.count == 1 { scores[producers[0]] += 1 }
        }
        if let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] > 0 {
            return best
        }
        if let current = currentSourceID,
           let index = maps.firstIndex(where: { $0.sourceID == current }) {
            return index
        }
        return nil
    }
}
