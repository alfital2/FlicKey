import Foundation

// Stores the activated license in the Keychain (survives app delete/reinstall,
// like the trial). Activation/validation go through Lemon Squeezy's license API.
// We cache "licensed" locally and only ever DROP it on an explicit invalid
// response (refund/revoke) — a network error never locks the user out.
enum LicenseStore {
    // UI tests get their own Keychain item so they can never read or clobber
    // the user's real license (mirrors AppDefaults.useIsolatedStoreForUITests).
    private static var service: String {
        UITestMode.isActive ? "com.talalfi.FlicKey.license.uitest"
                            : "com.talalfi.FlicKey.license"
    }
    private static let account = "license"
    private static let lastValidatedKey = "license.lastValidated"
    private static let revalidateInterval: TimeInterval = 3 * 24 * 60 * 60

    static let buyURL = URL(string: "https://flickey.lemonsqueezy.com/checkout/buy/b5eabf81-bc60-4a8e-b17e-e637774cb581")!

    struct Record: Codable, Equatable {
        let key: String
        let instanceID: String
        let name: String
        let email: String
    }

    enum ActivationResult {
        case success(Record)
        case failure(String)   // user-facing message
    }

    static var current: Record? {
        guard let data = Keychain.get(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static var isLicensed: Bool { current != nil }

    // Activate a pasted key online. Returns the record or a user-facing message.
    static func activate(_ rawKey: String) async -> ActivationResult {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return .failure("Enter your license key.") }
        do {
            let lic = try await LemonSqueezy.activate(key: key, instanceName: deviceName())
            guard lic.valid, let instance = lic.instanceID else {
                return .failure(lic.errorMessage ?? "That license key isn't valid.")
            }
            let record = Record(key: key, instanceID: instance,
                                name: lic.customerName ?? "", email: lic.customerEmail ?? "")
            save(record)
            AppDefaults.store.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
            return .success(record)
        } catch LemonSqueezy.LSError.wrongStore {
            return .failure("That key is for a different product.")
        } catch {
            return .failure("Couldn't reach the license server - check your connection and try again.")
        }
    }

    // Background re-check (throttled). Only de-licenses on an explicit invalid
    // result; offline/errors keep the user licensed.
    static func revalidateIfDue() {
        guard let record = current else { return }
        let now = Date().timeIntervalSince1970
        guard now - AppDefaults.store.double(forKey: lastValidatedKey) > revalidateInterval else { return }
        Task {
            do {
                let lic = try await LemonSqueezy.validate(key: record.key, instanceID: record.instanceID)
                AppDefaults.store.set(now, forKey: lastValidatedKey)
                if !lic.valid { clear() }     // refunded / revoked
            } catch {
                // network/parse error → leave the license intact
            }
        }
    }

    static func deactivate() {
        if let record = current {
            Task { await LemonSqueezy.deactivate(key: record.key, instanceID: record.instanceID) }
        }
        clear()
    }

    // MARK: - Private

    private static func save(_ record: Record) {
        if let data = try? JSONEncoder().encode(record) {
            Keychain.set(data, service: service, account: account)
        }
        notifyChanged()
    }

    private static func clear() {
        Keychain.delete(service: service, account: account)
        AppDefaults.store.removeObject(forKey: lastValidatedKey)
        notifyChanged()
    }

    // Fired whenever the license state changes (activated / deactivated / revoked)
    // so the app can re-evaluate entitlement and re-enable or gate features.
    private static func notifyChanged() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .licenseChanged, object: nil) }
    }

    private static func deviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }
}

extension Notification.Name {
    // Posted when the license state changes; observers re-evaluate entitlement.
    static let licenseChanged = Notification.Name("flickey.licenseChanged")
}
