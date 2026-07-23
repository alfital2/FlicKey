import IOKit

// Whether the laptop lid is currently closed (clamshell). Read fresh from IOKit's
// IOPMrootDomain "AppleClamshellState" property, which laptops publish and update
// as the lid moves. Desktops have no lid and omit the property, so this reads
// false there.
//
// Used to skip the trackpad haptic cue when the lid is shut: a tap on a closed
// built-in trackpad can't be felt, and the actuator may not fire at all.
enum LidState {
    static var isClosed: Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue(),
            CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return false }

        return CFBooleanGetValue((value as! CFBoolean))
    }
}
