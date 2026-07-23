import AppKit
import Sparkle

// Thin wrapper around Sparkle's standard updater — the in-app
// "download → install → relaunch" flow.
//
// Creating `Updater.shared` starts Sparkle and schedules the periodic
// background check (honoring the user's preference and the feed/public key in
// Info.plist: SUFeedURL, SUPublicEDKey). When a newer *signed* release is
// available, Sparkle shows its own update window and installs in place — the
// app's code-signing identity is unchanged, so the Accessibility (TCC) grant
// survives the update. The old "open the GitHub download page" flow is gone.
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
    }

    private var updater: SPUUpdater { controller.updater }

    /// Manual check from Settings — always shows UI (progress, "up to date", errors).
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Whether Sparkle checks for updates automatically in the background.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
}
