import AppKit

// Frameless, centered, auto-dismissing HUD — the AppKit equivalent of
// Hammerspoon's hs.alert.show, styled with Liquid Glass (macOS 26+) and a
// frosted-glass fallback on older systems.
enum Overlay {

    private static var current: NSPanel?

    static func show(_ message: String, symbol: String? = "keyboard", duration: TimeInterval = 1.4) {
        // XCUITest polls element existence roughly once per second; a 1.4s HUD
        // can slip between polls. Keep overlays up longer during UI tests only.
        let duration = UITestMode.isActive ? max(duration, 4.0) : duration
        DispatchQueue.main.async {
            current?.orderOut(nil)

            let content = makeContent(message: message, symbol: symbol)
            let size = content.frame.size
            let container = makeGlassContainer(size: size, content: content)

            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.contentView = container
            panel.center()

            // Fade + subtle scale-in.
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            current = panel

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    panel.orderOut(nil)
                    if current === panel { current = nil }
                })
            }
        }
    }

    // MARK: - Content (icon + label)

    private static func makeContent(message: String, symbol: String?) -> NSView {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
        label.sizeToFit()

        let iconView = makeIcon(symbol)
        let iconWidth = iconView?.frame.width ?? 0
        let spacing: CGFloat = iconView == nil ? 0 : 12

        let padX: CGFloat = 24
        let padY: CGFloat = 16
        let innerHeight = max(iconView?.frame.height ?? 0, label.frame.height)
        let size = NSSize(
            width: iconWidth + spacing + label.frame.width + padX * 2,
            height: innerHeight + padY * 2
        )

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        var x = padX
        if let iconView = iconView {
            iconView.frame.origin = NSPoint(x: x, y: (size.height - iconView.frame.height) / 2)
            content.addSubview(iconView)
            x += iconWidth + spacing
        }
        label.frame.origin = NSPoint(x: x, y: (size.height - label.frame.height) / 2)
        content.addSubview(label)
        return content
    }

    private static func makeIcon(_ symbol: String?) -> NSImageView? {
        guard let symbol = symbol,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else { return nil }

        let config = NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        let view = NSImageView(image: image.withSymbolConfiguration(config) ?? image)
        view.contentTintColor = .labelColor
        view.sizeToFit()
        return view
    }

    // MARK: - Glass container

    private static func makeGlassContainer(size: NSSize, content: NSView) -> NSView {
        let radius = size.height / 2 // pill / capsule

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = radius
            glass.contentView = content
            return glass
        } else {
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = radius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            return effect
        }
    }
}
