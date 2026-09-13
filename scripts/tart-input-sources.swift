import Carbon
import Foundation

// Guest-only setup; enable the two layouts used by the functional test fixtures.
guard ProcessInfo.processInfo.userName == "admin",
      FileManager.default.fileExists(atPath: "/Volumes/My Shared Files/source") else {
    fatalError("Run this helper only inside the test VM")
}
let wanted = ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew-PC"]
let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
for id in wanted {
    guard let source = sources.first(where: {
        guard let pointer = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String == id
    }) else { fatalError("Missing layout: \(id)") }
    precondition(TISEnableInputSource(source) == noErr, "Could not enable \(id)")
    if id == wanted[0] {
        precondition(TISSelectInputSource(source) == noErr, "Could not select ABC")
    }
    print("Enabled \(id)")
}
