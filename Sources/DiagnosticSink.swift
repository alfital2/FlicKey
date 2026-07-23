import AppKit

// Where a composed report goes. v1 is user-visible by design: the report is
// previewed, then handed to the macOS share sheet (email is the primary target)
// with a Save fallback. Swapping in an HTTP/Sentry sink later (for cross-user
// aggregation) means implementing this protocol only — the recorder, schema and
// composer don't change.
protocol DiagnosticSink {
    func deliver(_ report: DiagnosticReport, from window: NSWindow?)
}

final class ShareSheetEmailSink: DiagnosticSink {

    func deliver(_ report: DiagnosticReport, from window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Review your report"
        alert.informativeText = "This is exactly what will be sent. FlicKey never includes what you type."
        alert.addButton(withTitle: "Share…")
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isRichText = false
        text.string = report.body
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = text
        alert.accessoryView = scroll

        switch alert.runModal() {
        case .alertFirstButtonReturn:  share(report, from: window)
        case .alertSecondButtonReturn: save(report)
        default: break
        }
    }

    // Writes the JSON attachment to a fixed-name temp file. Returns nil when the
    // write fails so the caller attaches nothing: the file name is reused between
    // shares, and returning it unconditionally would silently attach a stale report
    // from an earlier share in place of this one.
    private func writeJSON(_ report: DiagnosticReport) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlicKey-report.json")
        do {
            try report.jsonData.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static let supportEmail = "flickey.support@gmail.com"

    private func share(_ report: DiagnosticReport, from window: NSWindow?) {
        // The body always carries the full report; the JSON is an extra attachment,
        // dropped if it could not be written rather than sent stale.
        var items: [Any] = [report.body]
        if let url = writeJSON(report) { items.append(url) }

        // Compose a new email straight to FlicKey support, prefilled with the
        // report body + JSON attachment.
        if let email = NSSharingService(named: .composeEmail), email.canPerform(withItems: items) {
            email.recipients = [Self.supportEmail]
            email.subject = report.subject
            email.perform(withItems: items)
            return
        }
        // No configured mail client → fall back to the system share sheet.
        let picker = NSSharingServicePicker(items: items)
        guard let anchor = (window ?? NSApp.keyWindow)?.contentView else { return }
        picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
    }

    private func save(_ report: DiagnosticReport) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FlicKey-report.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.jsonData.write(to: url)
        } catch {
            // Surface the failure instead of closing the panel as if it saved: on a
            // full or read-only disk the report would otherwise be lost silently.
            let alert = NSAlert()
            alert.messageText = "Couldn't save the report"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
