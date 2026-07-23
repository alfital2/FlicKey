import Foundation

// Opt-in state for the "Make FlicKey better" diagnostics. Everything defaults to
// OFF: nothing is recorded or sent unless the user explicitly turns it on. One
// recording toggle plus a random per-install identifier (not derived from any
// hardware or device ID) so a user can later request deletion of their data
// without needing an account.
enum DiagnosticConsent {
    private static let recordKey = "diagRecordEnabled"
    private static let installIDKey = "diagInstallID"
    private static let shareWordsKey = "shareBlockedWordsEnabled"

    // Master switch: may FlicKey record its recent decisions into the ring buffer?
    static var isRecordingEnabled: Bool {
        get { AppDefaults.store.bool(forKey: recordKey) }         // absent → false
        set { AppDefaults.store.set(newValue, forKey: recordKey) }
    }

    // Whether FlicKey may periodically OFFER to email us the words it wrongly
    // auto-fixed (the learned blocklist), so auto-switch can improve. ON by
    // default. This only enables the periodic prompt: nothing is ever sent without
    // the user seeing the exact words and pressing Send in their own mail client,
    // and the prompt itself (and the Improve tab) can turn it off.
    static var shareBlockedWordsEnabled: Bool {
        get {
            // Absent → ON by default; once the user flips it we honor their choice.
            guard AppDefaults.store.object(forKey: shareWordsKey) != nil else { return true }
            return AppDefaults.store.bool(forKey: shareWordsKey)
        }
        set { AppDefaults.store.set(newValue, forKey: shareWordsKey) }
    }

    // Random per-install UUID, created lazily on first read and then stable.
    static var installID: String {
        if let id = AppDefaults.store.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        AppDefaults.store.set(id, forKey: installIDKey)
        return id
    }
}
