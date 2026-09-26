import Foundation
import Security

// This test helper is signed with FlicKey's designated requirement so it can
// reset the app-owned synthetic trial in the disposable VM. Never distributed.
guard NSUserName() == "admin",
      FileManager.default.fileExists(atPath: "/Users/admin/.flickey-test-vm") else { exit(2) }
let args = CommandLine.arguments
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.talalfi.FlicKey.trial",
    kSecAttrAccount as String: "trial"
]
let data = Data((args.count == 2 ? args[1] : "{}").utf8)
let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
if status == errSecItemNotFound {
    var add = query
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let result = SecItemAdd(add as CFDictionary, nil)
    guard result == errSecSuccess else { print("Trial fixture restore failed: \(result)"); exit(4) }
} else if status != errSecSuccess {
    print("Trial fixture reset failed: \(status)")
    exit(3)
}
