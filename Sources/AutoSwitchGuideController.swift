import AppKit

// A small guide window shown when the user clicks the auto-switch warning. It
// opens alongside Keyboard settings and demonstrates — with an animated mock of
// the actual toggle — exactly what to turn off. We deliberately don't try to
// drive the real System Settings UI (fragile across macOS versions); a faithful
// in-app mock is robust and clear.
final class AutoSwitchGuideController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Disable macOS Auto-Switch"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentView = makeContent()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeContent() -> NSView {
        let title = NSTextField(wrappingLabelWithString:
            "Turn off “Automatically switch to a document’s input source”")
        title.font = .systemFont(ofSize: 15, weight: .bold)

        let body = NSTextField(wrappingLabelWithString:
            "macOS is switching your keyboard layout per document, which overrides "
            + "FlicKey’s per-site memory. In the Keyboard settings that just opened:")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor

        // Step 1: locate the "Input Sources … Edit…" row (mock of the real one).
        let step1 = NSTextField(labelWithString: "1.  Under Text Input, click Edit next to Input Sources:")
        step1.font = .systemFont(ofSize: 12)
        let editRow = makeEditRow()

        // Step 2: the exact toggle to turn off (animated mock).
        let step2 = NSTextField(labelWithString: "2.  Turn this switch off:")
        step2.font = .systemFont(ofSize: 12)
        let toggleRow = makeToggleRow()

        let openButton = NSButton(title: "Open Keyboard Settings",
                                  target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded

        let stack = NSStackView(views: [title, body, step1, editRow, step2, toggleRow, openButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        editRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        toggleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
        return container
    }

    // Mock of the Keyboard ▸ Text Input ▸ "Input Sources … Edit…" row.
    private func makeEditRow() -> NSView {
        let label = NSTextField(labelWithString: "Input Sources")
        label.font = .systemFont(ofSize: 12)

        let value = NSTextField(labelWithString: enabledSourcesText())
        value.font = .systemFont(ofSize: 12)
        value.textColor = .secondaryLabelColor

        // Emphasized so the eye lands on it immediately.
        let edit = NSButton(title: "Edit…", target: self, action: #selector(openSettings))
        edit.bezelStyle = .rounded
        edit.controlSize = .small
        edit.bezelColor = .controlAccentColor
        edit.setContentHuggingPriority(.required, for: .horizontal)

        let row = boxedRow([label, NSView(), value, edit])
        return row
    }

    // Mock of the exact toggle to disable (animated).
    private func makeToggleRow() -> NSView {
        let label = NSTextField(labelWithString: "Automatically switch to a document’s input source")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        return boxedRow([label, NSView(), AnimatedToggle()])
    }

    private func boxedRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        row.layer?.cornerRadius = 8
        row.layer?.borderWidth = 1
        row.layer?.borderColor = NSColor.separatorColor.cgColor
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return row
    }

    private func enabledSourcesText() -> String {
        let names = InputSourceCatalog.enabledSources().map { $0.localizedName }
        return names.isEmpty ? "ABC and Hebrew – PC" : names.joined(separator: " and ")
    }

    @objc private func openSettings() {
        OSAutoSwitch.openKeyboardSettings()
    }
}

// A small switch that animates on↔off on a loop, mirroring the macOS control.
private final class AnimatedToggle: NSView {
    private let track = CALayer()
    private let knob = CALayer()
    private var isOn = true
    private var timer: Timer?

    private let w: CGFloat = 42
    private let h: CGFloat = 26
    private var inset: CGFloat { 3 }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        wantsLayer = true
        track.frame = bounds
        track.cornerRadius = h / 2
        knob.frame = CGRect(x: inset, y: inset, width: h - inset * 2, height: h - inset * 2)
        knob.cornerRadius = (h - inset * 2) / 2
        knob.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(track)
        layer?.addSublayer(knob)
        apply(animated: false)
        timer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { [weak self] _ in
            self?.isOn.toggle()
            self?.apply(animated: true)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: w, height: h) }

    private func apply(animated: Bool) {
        let onX = w - (h - inset * 2) - inset
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.3)
        track.backgroundColor = (isOn ? NSColor.systemGreen : NSColor.systemGray).cgColor
        knob.frame.origin.x = isOn ? onX : inset
        CATransaction.commit()
    }

    deinit { timer?.invalidate() }
}
