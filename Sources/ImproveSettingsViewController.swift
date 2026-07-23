import AppKit

// The "Improve" settings tab: the opt-in "Make FlicKey better" controls. Default
// OFF, granular, plainly worded, one-click revocable. Reads/writes
// DiagnosticConsent and drives the report flow via Diag.reporter.
final class ImproveSettingsViewController: NSViewController {

    private let recordCheckbox = NSButton(
        checkboxWithTitle: "Record what FlicKey does (never what you type)",
        target: nil, action: nil)
    private let shareWordsCheckbox = NSButton(
        checkboxWithTitle: "Share words that shouldn't have been auto-fixed (helps auto-switch learn)",
        target: nil, action: nil)
    private let reportButton = NSButton(title: "Report a Bug…", target: nil, action: nil)
    private let installLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let header = sectionHeader("Make FlicKey Better")
        let blurb = NSTextField(wrappingLabelWithString:
            "Let FlicKey record what it does (app names, layouts, its decisions) to help fix "
            + "bugs. Never what you type, and nothing sends without your review.")
        blurb.font = .systemFont(ofSize: 12)
        blurb.textColor = .secondaryLabelColor

        recordCheckbox.target = self; recordCheckbox.action = #selector(toggleRecord)
        shareWordsCheckbox.target = self; shareWordsCheckbox.action = #selector(toggleShareWords)
        reportButton.target = self; reportButton.action = #selector(reportBug)
        reportButton.bezelStyle = .rounded

        let shareWordsBlurb = NSTextField(wrappingLabelWithString:
            "FlicKey occasionally offers to email us words it wrongly fixed, so it learns. "
            + "You see them first. On by default; turn off anytime.")
        shareWordsBlurb.font = .systemFont(ofSize: 11)
        shareWordsBlurb.textColor = .secondaryLabelColor

        installLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        installLabel.textColor = .tertiaryLabelColor
        installLabel.isSelectable = true

        let privacyNote = NSTextField(wrappingLabelWithString:
            "Reports include app and macOS version, enabled layouts, and a random install ID "
            + "(below). No account, no keystrokes, no message or web content.")
        privacyNote.font = .systemFont(ofSize: 11)
        privacyNote.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            header, blurb,
            spacer(8),
            recordCheckbox,
            spacer(8),
            reportButton,
            spacer(12),
            shareWordsCheckbox, shareWordsBlurb,
            spacer(10),
            privacyNote, installLabel,
        ])
        installSettingsPane(stack, cards: [], spacing: 10)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    private func refresh() {
        let recording = DiagnosticConsent.isRecordingEnabled
        recordCheckbox.state = recording ? .on : .off
        shareWordsCheckbox.state = DiagnosticConsent.shareBlockedWordsEnabled ? .on : .off
        reportButton.isEnabled = recording
        installLabel.stringValue = "Install ID: \(DiagnosticConsent.installID)"
    }

    @objc private func toggleShareWords() {
        DiagnosticConsent.shareBlockedWordsEnabled = shareWordsCheckbox.state == .on
    }

    @objc private func toggleRecord() {
        let on = recordCheckbox.state == .on
        DiagnosticConsent.isRecordingEnabled = on
        if !on {
            // Turning it off forgets everything already buffered.
            Diag.recorder.clear()
        }
        refresh()
    }

    @objc private func reportBug() {
        Diag.reporter.reportBug(from: view.window)
    }
}
