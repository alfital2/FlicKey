import AppKit

// The panel shown to a NEW user whose 30-day trial has elapsed without a
// purchase. The app keeps running (menu bar, Settings, updates); only the
// input-switching features are paused. This offers the one-time unlock and a way
// to enter a key. Existing (grandfathered) users never see this.
final class TrialEndedController: NSObject {

    // Called when the user chooses to enter a key they already have.
    var onEnterKey: (() -> Void)?

    private var panel: NSPanel?

    func present() {
        // Defer to the next runloop: a menu-bar (LSUIElement) app can't bring a
        // window forward while still inside applicationDidFinishLaunching.
        DispatchQueue.main.async { [weak self] in self?.show() }
    }

    private func show() {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "FlicKey"
        panel.isReleasedWhenClosed = false
        // Same class of bug as QA 0.5.0-1: panels hide-on-deactivate by default and
        // an LSUIElement app is often never active, so the paywall panel would
        // silently never render on a real launch.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        self.panel = panel

        let title = NSTextField(labelWithString: "Your free trial has ended")
        title.font = .systemFont(ofSize: 17, weight: .bold)

        let body = NSTextField(wrappingLabelWithString:
            "FlicKey is still here. The menu bar, settings, and updates keep working. "
            + "To bring back automatic layout switching and one-tap conversion, unlock "
            + "FlicKey with a one-time purchase. No subscription.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor

        let unlock = NSButton(title: "Unlock FlicKey", target: self, action: #selector(buy))
        unlock.bezelStyle = .rounded
        unlock.keyEquivalent = "\r"
        let enterKey = NSButton(title: "Enter a License Key", target: self, action: #selector(enterKey))
        enterKey.bezelStyle = .rounded
        let later = NSButton(title: "Not now", target: self, action: #selector(close))
        later.bezelStyle = .rounded
        let buttons = NSStackView(views: [later, NSView(), enterKey, unlock])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                           constant: -(stack.edgeInsets.left + stack.edgeInsets.right)),
        ])
        panel.contentView = container
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    @objc private func buy() { NSWorkspace.shared.open(LicenseStore.buyURL) }
    @objc private func enterKey() { onEnterKey?() }
    @objc private func close() { dismiss() }
}
