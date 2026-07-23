import AppKit
import Foundation

// App-wide diagnostics facade. Every call site logs through Diag.log(...), which
// is a no-op unless the user opted in. The report coordinator turns a snapshot of
// the buffer into a shareable report when the user asks for one.
enum Diag {

    // The single shared ring buffer plus the report coordinator.
    static let recorder = DiagnosticRecorder()
    static let reporter = DiagnosticReporter()

    static func log(_ event: DiagnosticEvent) {
        recorder.log(event)
        if DebugLog.enabled { DebugLog.event.notice("\(event.line, privacy: .public)") }
    }
}
