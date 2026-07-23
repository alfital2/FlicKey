import Foundation
import Carbon
import XCTest

// Narrate what a UI test is doing, so a screen-controlled run isn't a black box.
//   • the scripts surface it live (they grep for "STEP ▸"), and
//   • it shows as a labeled activity in the Xcode .xcresult report, so the whole
//     step-by-step transcript is readable after the run.
func step(_ message: String) {
    NSLog("STEP ▸ %@", message)
    XCTContext.runActivity(named: "▸ \(message)") { _ in }
}

// Poll a condition while pumping the run loop — for state changes that don't
// surface through waitForExistence (label/value flips, app termination).
func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
}

// The input-source ID string for a TIS source (e.g. com.apple.keylayout.ABC).
private func sourceID(_ src: TISInputSource) -> String {
    guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

private func isASCIICapable(_ src: TISInputSource) -> Bool {
    guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsASCIICapable) else { return false }
    return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
}

// Force the system keyboard to a Latin (ASCII-capable) layout so XCUITest
// typeText/typeKey produce the expected characters regardless of what layout
// the machine was left in (e.g. Hebrew). Prefer ABC.
func forceLatinInputSource() {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
    let target = list.first { sourceID($0) == "com.apple.keylayout.ABC" }
        ?? list.first { sourceID($0).hasPrefix("com.apple.keylayout.") && isASCIICapable($0) }
    if let target { TISSelectInputSource(target) }
}

// The currently-active keyboard input source ID (e.g. com.apple.keylayout.ABC).
func currentInputSourceID() -> String {
    guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
    return sourceID(cur)
}

// Select a specific enabled keyboard input source by ID — simulates the user
// switching layouts via the Input menu (fires the same TIS notification).
func selectInputSource(id: String) {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
          let target = list.first(where: { sourceID($0) == id }) else { return }
    TISSelectInputSource(target)
}

// Poll until the live keyboard input source becomes `id` (or time out).
func waitForSource(_ id: String, _ timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if currentInputSourceID() == id { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return currentInputSourceID() == id
}

// Synthesize a quick double-tap of Shift (FlicKey's default conversion
// trigger) via CGEvents. XCUITest's typeKey is too slow/jittery for the
// detector's 0.3s tap/gap windows; raw events give exact timing.
func doubleTapShift() {
    func tapShift() {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true)   // left Shift
        down?.flags = .maskShift
        down?.post(tap: .cghidEventTap)
        usleep(40_000)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false)
        up?.flags = []
        up?.post(tap: .cghidEventTap)
    }
    tapShift()
    usleep(120_000)
    tapShift()
}

// Two distinct enabled keyboard layouts to test a visible flip: a Latin one
// (ABC if present) and the first enabled non-Latin layout. Returns nil if the
// machine doesn't have two suitable layouts enabled.
func twoEnabledLayouts() -> (latin: String, other: String)? {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return nil }
    func enabled(_ s: TISInputSource) -> Bool {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceIsEnabled) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue() == kCFBooleanTrue
    }
    let layouts = list.filter { sourceID($0).hasPrefix("com.apple.keylayout.") && enabled($0) }
    let latin = layouts.first { sourceID($0) == "com.apple.keylayout.ABC" }
        ?? layouts.first { isASCIICapable($0) }
    let other = layouts.first { !isASCIICapable($0) }
        ?? layouts.first { sourceID($0) != sourceID(latin ?? $0) }
    guard let l = latin, let o = other, sourceID(l) != sourceID(o) else { return nil }
    return (sourceID(l), sourceID(o))
}

// Resolve a Settings tab by label, however macOS surfaces it in the current
// toolbar (a toolbar button, radio button, or plain button).
extension XCUIApplication {
    func tab(_ label: String) -> XCUIElement {
        for candidate in [toolbars.buttons[label], radioButtons[label], buttons[label]]
        where candidate.exists { return candidate }
        return toolbars.buttons[label]
    }
}

// Double-tap Shift and wait for the fix to land; one retry if it doesn't, since
// the detector can miss the very first synthetic pair right after launch (a human
// reflex is the same: tap again).
func triggerFix(until condition: @escaping () -> Bool) -> Bool {
    doubleTapShift()
    if waitUntil(timeout: 4, condition) { return true }
    step("  · fix didn't land, retrying ⇧⇧")
    doubleTapShift()
    return waitUntil(timeout: 6, condition)
}
