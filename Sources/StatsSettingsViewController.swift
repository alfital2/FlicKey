import AppKit

// The fun "stats" tab. Its toolbar label is the running total (kept fresh by
// SettingsTabViewController); this pane shows the big number and a per-kind
// breakdown of every layout change FlicKey has made for the user.
//
// QA BUG 0.5.0-3: the counts must track live. The pane refreshes on appear AND
// on every .switchStatsChanged, so a fix landing while the window is open is
// visible immediately (not only after an app relaunch).
final class StatsSettingsViewController: NSViewController {

    private let bigLabel = NSTextField(labelWithString: "0")
    private var valueLabels: [SwitchKind: NSTextField] = [:]
    private let nagCheckbox = NSButton(
        checkboxWithTitle: "Don't show milestone popups (\"FlicKey helped you N times\")",
        target: nil, action: nil)
    private var statsToken: NSObjectProtocol?

    override func loadView() {
        let header = sectionHeader("FlicKey at Work")

        bigLabel.font = roundedBold(40)
        bigLabel.textColor = .controlAccentColor
        bigLabel.setAccessibilityIdentifier("switchStatsTotal")

        let caption = NSTextField(labelWithString:
            "layout switches and fixes FlicKey handled for you, and counting")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor

        let rows: [NSView] = SwitchKind.allCases.map { kind in
            let glyph = NSImageView(image: NSImage(systemSymbolName: kind.symbol,
                                                   accessibilityDescription: nil) ?? NSImage())
            glyph.contentTintColor = .secondaryLabelColor
            let name = NSTextField(labelWithString: kind.label)
            let left = NSStackView(views: [glyph, name])
            left.orientation = .horizontal
            left.spacing = 8
            let value = NSTextField(labelWithString: "0")
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            valueLabels[kind] = value
            return settingsRow2(left, value)
        }
        let card = settingsCard(rows)

        nagCheckbox.target = self
        nagCheckbox.action = #selector(toggleNag)
        nagCheckbox.setAccessibilityIdentifier("disableStatsNags")

        let foot = settingsFootnote(
            "Counts auto-fixes, on-demand conversions (double-tap Shift), and per-app, "
            + "per-website and per-chat switches. All local; nothing is sent.")

        let stack = NSStackView(views: [header, bigLabel, caption, spacer(8), card,
                                        spacer(6), nagCheckbox, spacer(2), foot])
        installSettingsPane(stack, cards: [card])

        statsToken = NotificationCenter.default.addObserver(
            forName: .switchStatsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        if let statsToken { NotificationCenter.default.removeObserver(statsToken) }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    private func refresh() {
        bigLabel.stringValue = SwitchStats.total.formatted()
        for (kind, label) in valueLabels {
            label.stringValue = SwitchStats.count(kind).formatted()
        }
        nagCheckbox.state = StatsNagController.isDisabled ? .on : .off
    }

    @objc private func toggleNag() {
        StatsNagController.isDisabled = nagCheckbox.state == .on
    }

    private func roundedBold(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }
}

// A card row with an arbitrary leading view (not just a label) and a trailing
// control, mirroring settingsRow's column alignment.
func settingsRow2(_ leading: NSView, _ control: NSView) -> NSView {
    leading.setContentHuggingPriority(.defaultLow, for: .horizontal)
    control.setContentHuggingPriority(.required, for: .horizontal)
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
    row.addView(leading, in: .leading)
    row.addView(control, in: .trailing)
    row.translatesAutoresizingMaskIntoConstraints = false
    row.heightAnchor.constraint(equalToConstant: 34).isActive = true
    return row
}
