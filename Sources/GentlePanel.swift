import AppKit

// A small non-blocking prompt panel for launch-time reminders. Replaces the
// NSAlert.runModal() idiom, which QA proved twice (0.5.0 BUG-2, the 0.5.1 nag)
// silently starves the conversion pipeline while the alert waits - fatal for a
// menu-bar app whose alert may not even be visible. This panel:
//   - never runs a modal loop (conversion keeps working while it is open)
//   - never activates the app or steals keyboard focus (.nonactivatingPanel)
//   - is visible from a cold LaunchServices launch (hidesOnDeactivate = false)
final class GentlePanel: NSObject {

    private var panel: NSPanel?
    private var primaryAction: (() -> Void)?

    // Shows the panel (replacing any previous one from this instance).
    func show(title: String, body: String,
              primary: String, secondary: String,
              onPrimary: @escaping () -> Void) {
        dismiss()
        primaryAction = onPrimary

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
                            styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "FlicKey"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 15, weight: .bold)

        let bodyField = NSTextField(wrappingLabelWithString: body)
        bodyField.font = .systemFont(ofSize: 12)
        bodyField.textColor = .secondaryLabelColor

        let primaryButton = NSButton(title: primary, target: self, action: #selector(primaryTapped))
        primaryButton.bezelStyle = .rounded
        let secondaryButton = NSButton(title: secondary, target: self, action: #selector(close))
        secondaryButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [NSView(), secondaryButton, primaryButton])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [titleField, bodyField, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 16, right: 22)
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
        panel.orderFrontRegardless()   // deliberately no makeKey, no NSApp.activate
    }

    @objc private func primaryTapped() {
        primaryAction?()
        dismiss()
    }

    @objc private func close() { dismiss() }

    func dismiss() {
        panel?.close()
        panel = nil
        primaryAction = nil
    }
}
