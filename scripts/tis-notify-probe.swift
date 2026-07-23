#!/usr/bin/env swift
//
// tis-notify-probe.swift — measures the REAL behavior of the keyboard
// input-source change notification relative to our own switches, so the per-site
// "echo" guard can be designed to reality instead of guessed.
//
// It fires a controlled sequence of TISSelectInputSource calls (rapid / medium /
// slow) and logs every CALL and every resulting distributed notification
// (kTISNotifySelectedKeyboardInputSourceChanged) with monotonic timestamps and
// the current source at delivery. From the correlation we learn:
//   • apply → notification LATENCY (how long after our switch the echo lands)
//   • COALESCING (do N rapid switches yield N notifications, or fewer?)
//   • what the notification REPORTS (the applied source, or a later/current one?)
//
// Run with FlicKey QUIT so only this process switches the source (no interference).
// It toggles your layout briefly then restores the original — don't type during it.
//
//   swift scripts/tis-notify-probe.swift

import Foundation
import Carbon

setvbuf(stdout, nil, _IONBF, 0)

// MARK: - TIS helpers

func id(of source: TISInputSource) -> String {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func currentID() -> String {
    guard let s = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "none" }
    return id(of: s)
}

func short(_ s: String) -> String {
    s.replacingOccurrences(of: "com.apple.keylayout.", with: "")
}

func allSelectable() -> [TISInputSource] {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
    else { return [] }
    return list.filter { src in
        // keyboard layouts that are enabled + selectable
        func boolProp(_ key: CFString) -> Bool {
            guard let p = TISGetInputSourceProperty(src, key) else { return false }
            return CFBooleanGetValue((Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue()))
        }
        return boolProp(kTISPropertyInputSourceIsSelectCapable) && boolProp(kTISPropertyInputSourceIsEnabled)
    }
}

func select(_ sourceID: String) {
    for src in allSelectable() where id(of: src) == sourceID {
        TISSelectInputSource(src)
        return
    }
}

// MARK: - Globals for the C notification callback

let startTime = ProcessInfo.processInfo.systemUptime
func elapsed() -> Double { ProcessInfo.processInfo.systemUptime - startTime }
var lastApplyAt = -999.0
var lastApplyTarget = "—"

// MARK: - Pick two sources to toggle between

let selectable = allSelectable()
let ids = selectable.map { id(of: $0) }
let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew-PC"]
var a = preferred[0], b = preferred[1]
if !(ids.contains(a) && ids.contains(b)) {
    guard ids.count >= 2 else {
        print("Need at least two enabled keyboard layouts; found: \(ids.map(short))")
        exit(1)
    }
    a = ids[0]; b = ids[1]
}
let original = currentID()
print("Toggling between [\(short(a))] and [\(short(b))]; original = [\(short(original))]")
print("Columns: [apply] +<t> -> target   |   [note] +<t> reports=<src>  (+<ms> after last apply)\n")

// MARK: - Notification observer (reads current source at delivery)

let center = CFNotificationCenterGetDistributedCenter()
let cb: CFNotificationCallback = { _, _, _, _, _ in
    let t = elapsed()
    let cur = currentID()
    let since = (t - lastApplyAt) * 1000
    print(String(format: "[note]  +%.3f  reports=%@   (+%.0fms after apply of %@)",
                 t, short(cur), since, short(lastApplyTarget)))
}
CFNotificationCenterAddObserver(center, nil, cb,
    kTISNotifySelectedKeyboardInputSourceChanged, nil, .deliverImmediately)

// MARK: - Apply sequence

func apply(_ target: String) {
    lastApplyAt = elapsed()
    lastApplyTarget = target
    print(String(format: "[apply] +%.3f  -> %@", lastApplyAt, short(target)))
    select(target)
}

// (delay, target). Rapid (40ms), medium (200ms), slow (800ms).
let plan: [(Double, String)] = [
    (0.00, a), (0.04, b), (0.08, a), (0.12, b), (0.16, a), (0.20, b),   // rapid
    (0.70, a), (0.90, b), (1.10, a), (1.30, b),                          // medium
    (2.10, a), (2.90, b),                                                // slow
]
for (delay, target) in plan {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { apply(target) }
}

// Restore + summary after the last apply plus a settle window for trailing notes.
DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
    select(original)
    print("\nRestored original = [\(short(original))]. Done.")
    exit(0)
}

print("Running… (do not type; layout will toggle then restore)\n")
RunLoop.main.run()
