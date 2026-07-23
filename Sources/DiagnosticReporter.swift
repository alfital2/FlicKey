import AppKit

// Coordinates the manual "Report a bug" entry point: builds a report from the
// current buffer and hands it to the sink.
final class DiagnosticReporter {

    private let sink: DiagnosticSink

    init(sink: DiagnosticSink = ShareSheetEmailSink()) { self.sink = sink }

    // Manual: ask for an optional note, then compose + deliver.
    func reportBug(from window: NSWindow?) {
        guard DiagnosticConsent.isRecordingEnabled else {
            Overlay.show("Turn on “Record diagnostic events” first", symbol: "info.circle")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Report a bug"
        alert.informativeText = "Optionally describe what went wrong. FlicKey attaches a log of its recent decisions, never what you typed."
        alert.addButton(withTitle: "Next…")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        // Nudge beta users toward the detail that makes their report actionable.
        field.placeholderString = AutoSwitchSettings.isEnabled
            ? "e.g. auto-switch changed words I meant, or missed obvious ones"
            : "e.g. typed Hebrew in Teams but got English"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let note = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        compose(note: note.isEmpty ? nil : note, from: window)
    }

    private func compose(note: String?, from window: NSWindow?) {
        let report = ReportComposer.compose(entries: Diag.recorder.snapshot(),
                                            environment: .current(),
                                            note: note)
        sink.deliver(report, from: window)
    }
}
