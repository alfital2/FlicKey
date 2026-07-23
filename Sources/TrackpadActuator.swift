import Foundation
import IOKit

// Trackpad haptic taps that fire even when no finger rests on the trackpad.
//
// NSHapticFeedbackManager silently drops feedback unless the user is touching
// the trackpad — useless for a cue that fires while hands are on the keyboard.
// The private MultitouchSupport actuator (the HapticKey approach) taps the
// trackpad unconditionally. Verified on macOS 26: symbols resolve, and every
// actuation ID returns success (6 = the strong tap used here). Everything is
// resolved dynamically and fails soft: if the framework, symbols, or device
// vanish in a future macOS, tap() returns false and the caller falls back to
// NSHapticFeedbackManager.
//
// PRIVATE API — Developer ID build only. Do not port to the App Store edition
// (sandbox review rejects private frameworks).
final class TrackpadActuator {

    static let shared = TrackpadActuator()

    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private var actuate: ActuateFn?
    private var actuators: [CFTypeRef] = []

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW),
            let createPtr = dlsym(handle, "MTActuatorCreateFromDeviceID"),
            let openPtr = dlsym(handle, "MTActuatorOpen"),
            let actuatePtr = dlsym(handle, "MTActuatorActuate") else { return }
        let create = unsafeBitCast(createPtr, to: CreateFn.self)
        let open = unsafeBitCast(openPtr, to: OpenFn.self)

        // Open an actuator per multitouch device present at launch (built-in
        // trackpad and any connected Magic Trackpad), so the tap lands wherever
        // the user's hands are. A trackpad paired later isn't picked up until
        // relaunch — acceptable: the built-in one is always there on laptops.
        for id in Self.deviceIDs() {
            guard let actuator = create(id)?.takeRetainedValue(),
                  open(actuator) == 0 else { continue }
            actuators.append(actuator)
        }
        if !actuators.isEmpty {
            actuate = unsafeBitCast(actuatePtr, to: ActuateFn.self)
        }
    }

    // One physical tap on every open actuator, using the given waveform ID
    // (strength). False if none succeeded — the caller should fall back to
    // NSHapticFeedbackManager.
    @discardableResult
    func tap(actuationID: Int32 = 6) -> Bool {
        guard let actuate else { return false }
        var ok = false
        for actuator in actuators where actuate(actuator, actuationID, 0, 0, 0) == 0 {
            ok = true
        }
        return ok
    }

    private static func deviceIDs() -> [UInt64] {
        var ids: [UInt64] = []
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleMultitouchDevice"),
                                           &iter) == KERN_SUCCESS else { return ids }
        var service = IOIteratorNext(iter)
        while service != 0 {
            if let id = IORegistryEntryCreateCFProperty(
                service, "Multitouch ID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? UInt64 {
                ids.append(id)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
        return ids
    }
}
