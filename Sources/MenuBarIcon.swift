import AppKit

// How the menu-bar language badge is drawn. Persisted in defaults.
enum MenuBarIconStyle: String, CaseIterable {
    case brand        // fixed purple→blue brand gradient (default)
    case monochrome   // template glyph — macOS tints it to match the menu bar
    case perLanguage  // a deterministic gradient color per input language

    var displayName: String {
        switch self {
        case .brand:       return "Brand gradient"
        case .monochrome:  return "Monochrome"
        case .perLanguage: return "Color per language"
        }
    }
}

enum MenuBarIcon {
    private static let key = "menuBarIconStyle"

    static var style: MenuBarIconStyle {
        get { AppDefaults.store.string(forKey: key).flatMap(MenuBarIconStyle.init) ?? .brand }
        set {
            AppDefaults.store.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
        }
    }

    // A stable hue in [0,360) for an input source. Deterministic (FNV-1a hash of
    // the source ID → hue), so a language is ALWAYS the same color and different
    // languages get visibly different colors — the user learns "purple = Hebrew"
    // at a glance. Independent of which other layouts are enabled.
    static func hue(forSourceID id: String) -> Double {
        var hash: UInt64 = 1469598103934665603            // FNV-1a 64-bit offset basis
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Double(hash % 360)
    }

    // MARK: - Rendering

    static func badge(code: String, sourceID: String, style: MenuBarIconStyle) -> NSImage {
        let base = NSFont.systemFont(ofSize: 11, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 11) } ?? base
        let height: CGFloat = 18
        let badgeHeight: CGFloat = 16
        let padX: CGFloat = 6

        // Monochrome draws the code as a template glyph with no fill, so AppKit tints
        // it black or white to match the menu bar; the gradient styles fill a rounded
        // badge behind white text. One render path, branching only on text color, the
        // badge fill, and isTemplate.
        let isMono = (style == .monochrome)
        let textColor: NSColor = isMono ? .black : .white
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .kern: 0.5]
        let string = NSAttributedString(string: code, attributes: attrs)
        let textSize = string.size()
        let width = ceil(textSize.width) + padX * 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if !isMono {
            let badgeRect = NSRect(x: 0, y: (height - badgeHeight) / 2, width: width, height: badgeHeight)
            NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).addClip()
            let (start, end) = gradient(style: style, sourceID: sourceID)
            NSGradient(starting: start, ending: end)!.draw(in: badgeRect, angle: -45)
        }
        string.draw(at: NSPoint(x: (width - textSize.width) / 2, y: (height - textSize.height) / 2))
        image.unlockFocus()
        image.isTemplate = isMono
        return image
    }

    // Two-stop gradient. Per-language keeps the brand's vivid look and ~30° hue
    // sweep, just rotated to the language's deterministic hue.
    private static func gradient(style: MenuBarIconStyle, sourceID: String) -> (NSColor, NSColor) {
        switch style {
        case .perLanguage:
            let h = hue(forSourceID: sourceID) / 360.0
            let start = NSColor(hue: h, saturation: 0.72, brightness: 0.92, alpha: 1)
            let end = NSColor(hue: (h + 0.08).truncatingRemainder(dividingBy: 1.0),
                              saturation: 0.80, brightness: 0.98, alpha: 1)
            return (start, end)
        case .brand, .monochrome:
            return (NSColor(red: 0.40, green: 0.28, blue: 0.95, alpha: 1),
                    NSColor(red: 0.18, green: 0.62, blue: 0.98, alpha: 1))
        }
    }
}

extension Notification.Name {
    static let menuBarIconStyleChanged = Notification.Name("menuBarIconStyleChanged")
}
