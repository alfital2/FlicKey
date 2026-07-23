import OSLog
import Foundation

// Unified-logging (Console.app) mirror of the diagnostics trail, so a user who
// opted in can watch it live. Filter in Console by: subsystem:com.talalfi.FlicKey
//
// Only NON-SENSITIVE, categorical data goes here — the same allow-listed values
// as the in-app report (event types, app bundle IDs, input-source IDs, AX
// recovery). It never logs window titles / conversation names / typed text.
enum DebugLog {
    static let subsystem = "com.talalfi.FlicKey"

    static let recovery = Logger(subsystem: subsystem, category: "recovery")
    static let event    = Logger(subsystem: subsystem, category: "event")

    // Only emit when the user has opted into diagnostics. Read the flag directly
    // (rather than via DiagnosticConsent) so this file has no app-only deps and
    // can compile into the test targets that reuse the conversation providers.
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "diagRecordEnabled") }
}
