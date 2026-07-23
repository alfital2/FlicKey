import Foundation

// The UserDefaults all FlicKey stores read/write through. Normally the standard
// suite; UI tests point it at a throwaway suite (via a launch argument) so they
// can NEVER read or corrupt the user's real settings.
enum AppDefaults {
    private(set) static var store: UserDefaults = .standard

    // Call ONCE at launch, before any store is touched.
    static func useIsolatedStoreForUITests() {
        let suite = "com.talalfi.FlicKey.uitest"
        guard let isolated = UserDefaults(suiteName: suite) else { return }
        isolated.removePersistentDomain(forName: suite)   // clean slate each run
        store = isolated
    }
}
