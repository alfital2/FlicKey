import Foundation

// Auto-switch (beta) debugging context, attached to a report only while the
// beta is enabled — the toggle in General says so. Categorical facts only:
// which dictionaries actually work on this machine (the usual culprit when
// detection misbehaves) and how many exception words were learned. Never the
// words themselves; they are things the user typed.
struct AutoSwitchReportContext: Codable, Equatable {
    let functionalDictionaries: [String]
    let missingDictionaries: [String]
    let learnedExceptionCount: Int
}

// Non-sensitive environment facts included with a report.
struct DiagnosticEnvironment {
    let appVersion: String
    let osVersion: String
    let installID: String
    let enabledInputSources: [String]   // input-source IDs only
    let autoSwitchBeta: AutoSwitchReportContext?   // nil while the beta is off

    static func current() -> DiagnosticEnvironment {
        DiagnosticEnvironment(
            appVersion: DiagnosticRecorder.bundleVersion(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            installID: DiagnosticConsent.installID,
            enabledInputSources: InputSourceCatalog.enabledSources().map { $0.id },
            autoSwitchBeta: AutoSwitchSettings.isEnabled ? .current() : nil
        )
    }
}

extension AutoSwitchReportContext {
    // Snapshot the live dictionary health per enabled layout language.
    static func current(spellChecker: SpellChecking = SystemSpellChecker()) -> AutoSwitchReportContext {
        let languages = WordScript.primaryLanguages(of: InputSourceCatalog.enabledSources())
        return AutoSwitchReportContext(
            functionalDictionaries: languages.filter { spellChecker.hasFunctionalDictionary($0) },
            missingDictionaries: languages.filter { !spellChecker.hasFunctionalDictionary($0) },
            learnedExceptionCount: AutoSwitchExceptions().count
        )
    }
}

// A composed report: a human-readable body (email/preview) plus a structured
// JSON attachment. Both are derived only from DiagnosticEntry values.
struct DiagnosticReport: Equatable {
    let subject: String
    let body: String
    let jsonData: Data
}

// Turns a snapshot of the ring buffer into a report. Because DiagnosticEvent has
// no free-text field, there is nothing here to scrub; the composer just formats.
enum ReportComposer {

    static func compose(entries: [DiagnosticEntry],
                        environment: DiagnosticEnvironment,
                        note: String? = nil) -> DiagnosticReport {

        let subject = "FlicKey report [\(environment.appVersion)]"

        var b = ""
        b += "FlicKey diagnostic report\n"
        b += "=========================\n\n"
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            b += "What happened\n-------------\n\(note)\n\n"
        }
        b += "Environment\n-----------\n"
        b += "App:      \(environment.appVersion)\n"
        b += "macOS:    \(environment.osVersion)\n"
        b += "Install:  \(environment.installID)\n"
        b += "Layouts:  \(environment.enabledInputSources.joined(separator: ", "))\n\n"

        if let beta = environment.autoSwitchBeta {
            b += "Auto-switch (beta)\n------------------\n"
            b += "Working dictionaries:  \(beta.functionalDictionaries.isEmpty ? "none" : beta.functionalDictionaries.joined(separator: ", "))\n"
            b += "Missing dictionaries:  \(beta.missingDictionaries.isEmpty ? "none" : beta.missingDictionaries.joined(separator: ", "))\n"
            b += "Learned exceptions:    \(beta.learnedExceptionCount)\n\n"
        }

        b += "Activity (\(entries.count) events)\n---------\n"
        for e in entries { b += "  \(timestamp(e.at))  \(e.event.line)\n" }
        b += "\n"
        b += "FlicKey never records what you type. This report contains only app "
        b += "decisions, app bundle IDs, and keyboard-layout identifiers.\n"

        let payload = ReportPayload(
            installID: environment.installID,
            appVersion: environment.appVersion,
            osVersion: environment.osVersion,
            enabledInputSources: environment.enabledInputSources,
            autoSwitchBeta: environment.autoSwitchBeta,
            note: note,
            entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // ReportPayload is built entirely from Codable value types with no custom or
        // throwing encode paths, so encoding cannot fail. try! documents that: if the
        // schema ever gains an unencodable field, tests trip here instead of shipping
        // an empty attachment.
        let json = try! encoder.encode(payload)

        return DiagnosticReport(subject: subject, body: b, jsonData: json)
    }

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: date)
    }
}

// The JSON attachment shape. Kept private to the composer so the wire format has
// a single owner.
private struct ReportPayload: Codable {
    let installID: String
    let appVersion: String
    let osVersion: String
    let enabledInputSources: [String]
    let autoSwitchBeta: AutoSwitchReportContext?
    let note: String?
    let entries: [DiagnosticEntry]
}
