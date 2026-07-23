import Foundation
import OSLog
import ServiceManagement

// Real login-item registration via SMAppService (macOS 13+). Registering the
// main app makes macOS launch FlicKey automatically at login.
enum LaunchAtLogin {

    private static let log = Logger(subsystem: "com.talalfi.FlicKey", category: "launch")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
