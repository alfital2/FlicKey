import Foundation

// Lemon Squeezy license API client. The activate/validate/deactivate endpoints
// take only the license key (no secret), so nothing private ships in the app.
// Parsing is split out as a pure function so it's unit-testable against captured
// real responses.
struct LSLicense: Equatable {
    let valid: Bool
    let errorMessage: String?
    let storeID: Int?
    let productName: String?
    let customerName: String?
    let customerEmail: String?
    let instanceID: String?
}

enum LemonSqueezy {
    // This store only. Gates out license keys from any other Lemon Squeezy seller.
    static let expectedStoreID = 400531
    private static let base = "https://api.lemonsqueezy.com/v1/licenses"

    enum LSError: Error, Equatable { case wrongStore, malformed }
    enum Kind { case activate, validate }

    static func activate(key: String, instanceName: String) async throws -> LSLicense {
        try await post("/activate", ["license_key": key, "instance_name": instanceName], kind: .activate)
    }

    static func validate(key: String, instanceID: String?) async throws -> LSLicense {
        var fields = ["license_key": key]
        if let instanceID { fields["instance_id"] = instanceID }
        return try await post("/validate", fields, kind: .validate)
    }

    static func deactivate(key: String, instanceID: String) async {
        // Best-effort by design: freeing the server-side activation seat is a
        // courtesy, not a correctness requirement. The caller removes the license
        // locally whether or not this call succeeds, so deactivating while offline
        // is never blocked. A failure here only leaves one seat marked active on the
        // server until the next validate reconciles it.
        _ = try? await post("/deactivate", ["license_key": key, "instance_id": instanceID], kind: .validate)
    }

    // MARK: - Pure parsing

    static func parse(_ data: Data, kind: Kind) throws -> LSLicense {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let r = try? decoder.decode(Response.self, from: data) else { throw LSError.malformed }
        let ok = (kind == .activate) ? (r.activated ?? false) : (r.valid ?? false)
        if ok, let store = r.meta?.storeId, store != expectedStoreID { throw LSError.wrongStore }
        return LSLicense(valid: ok,
                         errorMessage: r.error,
                         storeID: r.meta?.storeId,
                         productName: r.meta?.productName,
                         customerName: r.meta?.customerName,
                         customerEmail: r.meta?.customerEmail,
                         instanceID: r.instance?.id)
    }

    private struct Response: Decodable {
        let activated: Bool?
        let valid: Bool?
        let error: String?
        let instance: Inst?
        let meta: Meta?
        struct Inst: Decodable { let id: String }
        struct Meta: Decodable {
            let storeId: Int
            let productName: String
            let customerName: String
            let customerEmail: String
        }
    }

    // MARK: - Networking

    private static func post(_ path: String, _ fields: [String: String], kind: Kind) async throws -> LSLicense {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\(formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try parse(data, kind: kind)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
