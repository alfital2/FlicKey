import CryptoKit
import Foundation

// Produces a SHORT, irreversible token for a sensitive identifier (a conversation
// name, a browser-tab domain) so the diagnostic trail can show WHEN the identity
// changed without ever revealing WHAT it is. SHA-256 over a per-install random
// salt plus the value, truncated to a few hex characters:
//   - irreversible: the digest can't be inverted, and truncation is lossy;
//   - un-guessable: without the salt — which never leaves the machine (never
//     logged, never in a bug report) — even a dictionary of likely names can't be
//     matched against the token, so who the user talks to can never be recovered;
//   - stable within an install: the same value always yields the same token, so a
//     reader can watch it change (or fail to change) across events;
//   - short: a few hex chars, so it never bloats a log line.
enum DiagnosticHash {
    private static let tokenBytes = 3          // 3 bytes → 6 hex characters
    private static let saltKey = "diagnosticHashSalt"

    // Token for a value using the per-install salt. The salt is created on first
    // use and kept only on this machine.
    static func token(_ value: String) -> String {
        token(value, salt: salt())
    }

    // Pure core (salt injected) so the hashing is deterministically unit-testable.
    static func token(_ value: String, salt: String) -> String {
        // NUL separates salt from value so no (salt, value) pair collides with a
        // different split of the same bytes.
        let digest = SHA256.hash(data: Data("\(salt)\u{0}\(value)".utf8))
        return digest.prefix(tokenBytes).map { String(format: "%02x", $0) }.joined()
    }

    // Per-install random salt, generated once and persisted locally. Deliberately
    // NOT the install ID (which is included in bug reports): the salt must never be
    // knowable to anyone who sees the logs, or the tokens could be brute-forced.
    private static func salt(store: UserDefaults = AppDefaults.store) -> String {
        if let existing = store.string(forKey: saltKey) { return existing }
        let fresh = UUID().uuidString + UUID().uuidString
        store.set(fresh, forKey: saltKey)
        return fresh
    }
}
