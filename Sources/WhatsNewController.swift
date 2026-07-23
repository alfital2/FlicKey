import AppKit

// Where the "seen" state for the what's new note lives. Per user, in defaults.
enum WhatsNewStore {
    private static let key = "whatsNewSeenVersion"
    static var seenVersion: String? {
        get { AppDefaults.store.string(forKey: key) }
        set { AppDefaults.store.set(newValue, forKey: key) }
    }
}

// Presents the one-time "what's new" popup when the developer has set a note for
// this release and the user has not seen it. Reusable for every future release:
// only the note in WhatsNew.current changes.
enum WhatsNewController {

    // Returns true if a note is due (so the caller can avoid stacking another
    // launch popup on top of it). Marks the note seen immediately, so it shows at
    // most once even if dismissed without a click.
    @discardableResult
    static func showIfNeeded() -> Bool {
        guard !UITestMode.isActive,
              let note = WhatsNew.current,
              WhatsNew.shouldShow(current: note, seenVersion: WhatsNewStore.seenVersion)
        else { return false }
        // Marked seen on DISMISS, not here: if presentation fails (or the app dies
        // first), the note must survive for the next launch instead of burning.
        // A menu-bar (LSUIElement) app can't reliably bring a window forward during
        // launch, so wait for the run loop to settle, then present.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { present(note) }
        return true
    }

    private static var panel: NSPanel?
    private static var fireworksTimer: Timer?
    private static var fireworksOverlay: NSView?

    private static func present(_ note: WhatsNewNote) {
        let width: CGFloat = 460
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "FlicKey"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        // QA BUG 0.5.0-1: NSPanel hides on deactivate by DEFAULT, and an LSUIElement
        // app launched from Finder/Dock is never active (cooperative activation
        // denies NSApp.activate at launch) — so without this line the panel exists
        // but the window server never shows it to a real user.
        panel.hidesOnDeactivate = false
        panel.delegate = Trampoline.shared   // stop fireworks if closed via the red button
        self.panel = panel

        let header = gradientHeader(note: note, width: width)

        let rows = NSStackView(views: note.items.map(featureRow))
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 16

        let gotIt = NSButton(title: "Got it", target: Trampoline.shared, action: #selector(Trampoline.close))
        gotIt.bezelStyle = .rounded
        gotIt.keyEquivalent = "\r"
        gotIt.controlSize = .large
        let buttonRow = NSStackView(views: [NSView(), gotIt])
        buttonRow.orientation = .horizontal

        let body = NSStackView(views: [rows, buttonRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 22
        body.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 22, right: 26)
        body.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(header)
        content.addSubview(body)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 150),
            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: body.widthAnchor,
                                        constant: -(body.edgeInsets.left + body.edgeInsets.right)),
            buttonRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
        ])

        panel.contentView = content
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // A little celebration over the header once layout has settled.
        DispatchQueue.main.async { celebrate(over: content) }
    }

    // Continuous firework bursts over the popup: colorful sparks that fan out and
    // fall. Keeps going until the user dismisses (Got it or the close button),
    // which stops the timer and tears the overlay down. The sparks live in a
    // pass-through overlay added ON TOP of the header/body, so they render above
    // them (a layer added straight to the content layer sits behind the subviews
    // and never shows).
    private static func celebrate(over content: NSView) {
        guard let spark = sparkImage() else { return }
        let overlay = PassThroughView(frame: content.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        content.addSubview(overlay)   // last subview -> topmost
        fireworksOverlay = overlay
        let palette: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .white,
                                  .systemOrange, .systemPurple, .systemGreen]

        let headerHeight: CGFloat = 150
        func burst() {
            let w = overlay.bounds.width, h = overlay.bounds.height
            guard w > 0, h > 0 else { return }
            // Originate only from the header band (the top gradient section).
            let point = CGPoint(x: CGFloat.random(in: w * 0.18 ... w * 0.82),
                                y: CGFloat.random(in: (h - headerHeight + 15) ... (h - 25)))
            let emitter = CAEmitterLayer()
            emitter.frame = overlay.bounds                 // WITHOUT this the sparks never appear
            emitter.emitterPosition = point
            emitter.emitterShape = .point
            emitter.renderMode = .additive
            emitter.emitterCells = palette.shuffled().prefix(4).map { color in
                let cell = CAEmitterCell()
                cell.contents = spark
                cell.color = color.cgColor
                cell.birthRate = 600
                cell.lifetime = 1.3
                cell.velocity = 150
                cell.velocityRange = 60
                cell.emissionRange = .pi * 2
                cell.yAcceleration = -260        // gravity (layer y points up)
                cell.scale = 0.55
                cell.scaleRange = 0.2
                cell.scaleSpeed = -0.3
                cell.alphaSpeed = -0.75
                cell.spin = 2
                cell.spinRange = 4
                return cell
            }
            overlay.layer?.addSublayer(emitter)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { emitter.birthRate = 0 } // one puff
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { emitter.removeFromSuperlayer() }
        }

        burst()   // fire immediately, then a lively cadence for ~2 seconds
        fireworksTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in burst() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            fireworksTimer?.invalidate(); fireworksTimer = nil        // stop launching new bursts
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {    // let the last sparks fall
                fireworksOverlay?.removeFromSuperview(); fireworksOverlay = nil
            }
        }
    }

    private static func stopFireworks() {
        fireworksTimer?.invalidate(); fireworksTimer = nil
        fireworksOverlay?.removeFromSuperview(); fireworksOverlay = nil
    }

    // A transparent overlay that never intercepts clicks, so the "Got it" button
    // underneath stays usable while the fireworks play on top.
    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private static func sparkImage(diameter: CGFloat = 8) -> CGImage? {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // A cheerful blue-to-purple banner with the app icon, title and subtitle.
    private static func gradientHeader(note: WhatsNewNote, width: CGFloat) -> NSView {
        let view = GradientView()
        view.colors = [
            NSColor(srgbRed: 0.32, green: 0.44, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.60, green: 0.35, blue: 0.96, alpha: 1),
        ]

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: note.title)
        title.font = roundedFont(size: 24, weight: .bold)
        title.textColor = .white

        var titleViews: [NSView] = [title]
        if !note.subtitle.isEmpty {
            let subtitle = NSTextField(labelWithString: note.subtitle)
            subtitle.font = roundedFont(size: 13, weight: .medium)
            subtitle.textColor = NSColor.white.withAlphaComponent(0.85)
            titleViews.append(subtitle)
        }
        let text = NSStackView(views: titleViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let stack = NSStackView(views: [icon, text])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private static func featureRow(_ item: WhatsNewItem) -> NSView {
        let glyph = NSImageView(image: NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
                                ?? NSImage())
        glyph.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        glyph.contentTintColor = .controlAccentColor
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.widthAnchor.constraint(equalToConstant: 26).isActive = true
        glyph.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(wrappingLabelWithString: item.text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor

        let row = NSStackView(views: [glyph, label])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    // SF Rounded when available, so the headline reads friendly, not system-stern.
    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func dismiss() {
        // The note is consumed only once the user has actually seen the panel and
        // it is going away — a presentation that never reached the screen retries
        // next launch instead of burning the announcement.
        if let note = WhatsNew.current { WhatsNewStore.seenVersion = note.version }
        stopFireworks()
        panel?.close()
        panel = nil
    }

    // NSButton targets and the window delegate need an @objc receiver; a tiny
    // singleton keeps the enum (which can't be a target) out of the wiring.
    private final class Trampoline: NSObject, NSWindowDelegate {
        static let shared = Trampoline()
        @objc func close() { WhatsNewController.dismiss() }
        // The red close button skips dismiss(), but the user did see the panel —
        // consume the note here too so it doesn't reappear next launch.
        func windowWillClose(_ notification: Notification) {
            if let note = WhatsNew.current { WhatsNewStore.seenVersion = note.version }
            WhatsNewController.stopFireworks()
        }
    }
}

// A layer-backed view that paints a diagonal gradient. Redraws on appearance
// changes so it stays correct across light/dark and window moves.
private final class GradientView: NSView {
    var colors: [NSColor] = [] { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer = gradient
    }
}
