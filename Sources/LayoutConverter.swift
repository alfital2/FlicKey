import Carbon
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
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard InputSourceCatalog.string(source, kTISPropertyInputSourceCategory)
                    == (kTISCategoryKeyboardInputSource as String),
                  let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selectable).takeUnretainedValue()),
                  let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabled).takeUnretainedValue()),
                  let id = InputSourceCatalog.string(source, kTISPropertyInputSourceID)
            else { return nil }
            return LayoutMap.forSource(id)
        }
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
        let maps = enabledMaps()
        guard maps.contains(where: { $0.sourceID == currentSourceID }) else { return nil }
        return convert(text, maps: maps, currentSourceID: currentSourceID)
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
        let maps = enabledMaps(), current = InputSourceManager.currentSourceID()
        guard maps.contains(where: { $0.sourceID == current }) else { return [] }
        return candidates(text, maps: maps, currentSourceID: current)
    }

    static func candidates(_ text: String, maps: [LayoutMap], currentSourceID: String?)
        -> [(converted: String, targetSourceID: String?)] {
        guard maps.count >= 2,
              let sourceIndex = sourceIndex(of: text, in: maps, currentSourceID: currentSourceID)
        else { return [] }
        return maps.indices.flatMap { index -> [(String, String?)] in
            guard index != sourceIndex else { return [] }
            // Automatic edits must not mistake a pruned search for unique
            // evidence. Oversized/ambiguous searches require manual conversion.
            return parses(of: text, from: maps[sourceIndex], to: maps[index], requireComplete: true)
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

    // Resolve each word with the caller's dictionary; preserve the deterministic
    // physical-key fallback when no single reading is supported by that evidence.
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
        let source = maps[sourceIndex]
        // Resolve each word independently while retaining every separator. This
        // allows "bad night" to use b in one word and g+h in the next, without a
        // phrase-wide combinatorial explosion or rewriting whitespace.
        var result = "", token = ""
        func appendToken() {
            guard !token.isEmpty else { return }
            let options = parses(of: token, from: source, to: target)
            if options.count == 1 {
                result += options[0]
                token = ""
                return
            }
            let validated = options.filter(isRealWord)
            // An explicit request still has a deterministic fallback. Automatic
            // detection requires a unique validated candidate before firing.
            result += validated.count == 1 ? validated[0] : options[0]
            token = ""
        }
        for character in text {
            if character.isWhitespace { appendToken(); result.append(character) }
            else { token.append(character) }
        }
        appendToken()
        return (result, id)
    }

    private enum Piece {
        case keys([KeyboardStroke])
        case literal(String)
    }

    private struct Path {
        var pieces: [Piece] = []
        var cost = 0
    }

    // Unicode scalars are the matching units, so a Thai vowel or Indic virama
    // remains independently recoverable even when Swift groups it with a letter.
    // Composed characters also have indexed multi-key readings from macOS.
    private static func convert(_ text: String, from source: LayoutMap, to target: LayoutMap) -> String {
        render(defaultPath(text, from: source, to: target).pieces, on: target)
    }

    private static func piece(for reading: KeyboardTransducer.Reading, original: String,
                              target: LayoutMap, adaptCase: Bool, captured: Bool = false) -> Piece {
        var strokes = reading.strokes
        if adaptCase, original.count == 1, original.first?.isUppercase == true,
           strokes.count == 1, !strokes[0].option {
            var baseStroke = strokes[0]
            baseStroke.shift = false
            baseStroke.capsLock = false
            if let base = target.transducer.standalone(baseStroke) {
                let shifted = target.transducer.standalone(strokes[0]) ?? ""
                let echoesLatin = !shifted.isEmpty && shifted.allSatisfy { $0.isASCII && $0.isLetter }
                    && base != shifted.lowercased()
                if shifted.isEmpty, base.contains(where: { $0.isLetter }) {
                    return .literal(base.uppercased())
                }
                // Explicit manual conversion of Latin capitals into a caseless
                // script has historically meant letters. Hebrew also echoes
                // Latin on Shift+Q/W, whose base outputs are punctuation. Raw
                // physical replay remains available separately from correction.
                if echoesLatin || (!captured && base.contains(where: { $0.isLetter }) && base.uppercased() == base) {
                    strokes[0] = baseStroke
                }
            }
        }
        guard strokes.allSatisfy({ stroke in
            guard let text = target.transducer.standalone(stroke), !text.isEmpty else { return false }
            return text.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control }
        }) else {
            return .literal(original)
        }
        return .keys(strokes)
    }

    private static func scalarString(_ scalars: ArraySlice<UInt32>) -> String {
        String(String.UnicodeScalarView(scalars.compactMap(Unicode.Scalar.init)))
    }

    private static func defaultPath(_ text: String, from source: LayoutMap, to target: LayoutMap) -> Path {
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
        var path = Path(), index = 0
        while index < scalars.count {
            if let reading = source.transducer.readings(in: scalars, at: index).first {
                let end = index + reading.scalars.count
                path.pieces.append(piece(for: reading, original: scalarString(scalars[index..<end]),
                                         target: target, adaptCase: true))
                path.cost += reading.cost
                index = end
            } else {
                path.pieces.append(.literal(scalarString(scalars[index..<(index + 1)])))
                index += 1
            }
        }
        return path
    }

    private static func render(_ pieces: [Piece], on target: LayoutMap, prefixIdentity: Bool = false) -> String {
        var result = "", pending: [KeyboardStroke] = []
        func flush() {
            result += target.transducer.render(pending) ?? ""
            pending.removeAll(keepingCapacity: true)
        }
        for piece in pieces {
            switch piece {
            case .keys(let strokes): pending += strokes
            case .literal(let text): flush(); result += text
            }
        }
        if prefixIdentity { result += target.transducer.prefixIdentity(pending) ?? "" }
        else { flush() }
        return result
    }

    // Bounded lattice of local readings, rather than just "split everything" and
    // "collapse everything". A word such as bright requires both Arabic choices.
    // The default is always first; callers can use dictionaries to disambiguate.
    static func parses(of text: String, from source: LayoutMap, to target: LayoutMap,
                       requireComplete: Bool = false) -> [String] {
        let baseline = convert(text, from: source, to: target)
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
        guard !scalars.isEmpty, scalars.count <= 256 else { return requireComplete ? [] : [baseline] }
        let limit = 64
        var expansions = 0
        var paths = [[Path]](repeating: [], count: scalars.count + 1)
        paths[0] = [Path()]
        for index in scalars.indices {
            // Deduplicate rendered prefixes before expanding: many physical
            // alternatives produce the same target, especially shifted digits.
            var seen = Set<String>()
            let unique = paths[index].sorted { $0.cost < $1.cost }.filter {
                seen.insert(render($0.pieces, on: target, prefixIdentity: true)).inserted
            }
            if requireComplete, unique.count > limit { return [] }
            let current = unique.prefix(limit)
            let readings = source.transducer.readings(in: scalars, at: index)
            for path in current {
                if readings.isEmpty {
                    var next = path
                    next.pieces.append(.literal(scalarString(scalars[index..<(index + 1)])))
                    paths[index + 1].append(next)
                }
                for reading in readings {
                    let end = index + reading.scalars.count
                    let original = scalarString(scalars[index..<end])
                    for adaptCase in original.first?.isUppercase == true ? [true, false] : [true] {
                        expansions += 1
                        if expansions > 8192 { return requireComplete ? [] : [baseline] }
                        var next = path
                        next.pieces.append(piece(for: reading, original: original, target: target, adaptCase: adaptCase))
                        next.cost += reading.cost
                        paths[end].append(next)
                    }
                }
            }
            paths[index] = []
        }
        var seen: Set<String> = [baseline]
        var result = [baseline]
        for path in paths[scalars.count].sorted(by: { $0.cost < $1.cost }) {
            let text = render(path.pieces, on: target)
            if seen.insert(text).inserted {
                if result.count >= limit { return requireComplete ? [] : result }
                result.append(text)
            }
        }
        return result
    }

    // Recorded keys are stronger evidence than dictionaries, but only when
    // replaying them reproduces the exact source text. No stale or edited trace
    // may influence a conversion, and IMEs never enter this physical-layout path.
    static func convertCaptured(_ text: String, strokes: [KeyboardStroke],
                                from source: LayoutMap, to target: LayoutMap,
                                applyingCorrectionPolicy: Bool = false) -> String? {
        guard !strokes.isEmpty, source.transducer.render(strokes) == text else { return nil }
        if applyingCorrectionPolicy {
            let pieces = strokes.enumerated().map { index, stroke in
                let original = source.transducer.standalone(stroke) ?? ""
                let composesTargetLetter: Bool = {
                    guard target.transducer.isDeadKey(stroke), index + 1 < strokes.count,
                          let composed = target.transducer.render([stroke, strokes[index + 1]])
                    else { return false }
                    return composed.count == 1 && composed.first?.isLetter == true
                }()
                if stroke.option, !source.transducer.isDeadKey(stroke),
                   !composesTargetLetter,
                   !original.unicodeScalars.allSatisfy({
                       CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                   }) { return Piece.literal(original) }
                return piece(for: KeyboardTransducer.Reading(scalars: [], strokes: [stroke], cost: 0),
                             original: original, target: target, adaptCase: true, captured: true)
            }
            return render(pieces, on: target)
        }
        return target.transducer.render(strokes)
    }

    static func convertCaptured(_ text: String, toSourceID id: String,
                                strokes: [KeyboardStroke]?) -> (converted: String, targetSourceID: String?)? {
        guard let strokes, let current = InputSourceManager.currentSourceID(), current != id,
              let source = LayoutMap.forSource(current), let target = LayoutMap.forSource(id),
              let text = convertCaptured(text, strokes: strokes, from: source, to: target,
                                          applyingCorrectionPolicy: true)
        else { return nil }
        return (text, id)
    }

    // The layout the text was (mistakenly) typed in: the one with the most
    // characters exclusive to it. Ties / none (pure punctuation, or near-identical
    // layouts like RU+UA that share most letters) → the current layout.
    private static func sourceIndex(of text: String, in maps: [LayoutMap],
                                    currentSourceID: String?) -> Int? {
        var scores = [Int](repeating: 0, count: maps.count)
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            let s = String(scalar)
            let producers = maps.indices.filter { maps[$0].producedCharacters.contains(s) }
            if producers.count == 1 { scores[producers[0]] += 1 }
        }
        let high = scores.max() ?? 0
        let leaders = scores.indices.filter { scores[$0] == high }
        if high > 0, leaders.count == 1 { return leaders[0] }
        if let current = currentSourceID,
           let index = maps.firstIndex(where: { $0.sourceID == current }) {
            return index
        }
        return nil
    }
}
