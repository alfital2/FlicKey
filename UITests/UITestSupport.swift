import Foundation
import Carbon
import Network
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

func inputSourceName(id: String) -> String? {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first(where: { sourceID($0) == id }),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
    else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
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

// Revert the most recent automatic correction.
func doubleTapOption() {
    func tapOption() {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: true)
        down?.flags = .maskAlternate
        down?.post(tap: .cghidEventTap)
        usleep(40_000)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: false)
        up?.flags = []
        up?.post(tap: .cghidEventTap)
    }
    tapOption()
    usleep(120_000)
    tapOption()
}

// Send a physical shortcut independent of the active character layout. This is
// important for browser shortcuts exercised while a remembered Hebrew/Russian
// layout is active: XCUI's character-based typeKey("t") need not map to the
// physical T key in that state.
func postPhysicalShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(40_000)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
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

// Tiny deterministic HTTP fixture for browser UI tests. `localhost` and the
// loopback address are deliberately separate site-memory keys, while both stay
// offline and avoid relying on wildcard-localhost DNS behavior in browsers.
final class LocalWebServer {
    private let listener: NWListener
    private let queue: DispatchQueue
    let port: UInt16

    init() throws {
        let worker = DispatchQueue(label: "com.talalfi.FlicKeyUITests.web")
        queue = worker
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: worker)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let title = request.contains("Host: 127.0.0.1") ? "FlicKey Site Two" : "FlicKey Site One"
                let body = "<html><head><title>\(title)</title></head><body>\(title)</body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            throw NSError(domain: "LocalWebServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "listener did not become ready"])
        }
        if let failure { listener.cancel(); throw failure }
        guard let raw = listener.port?.rawValue else {
            listener.cancel()
            throw NSError(domain: "LocalWebServer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "listener has no port"])
        }
        port = raw
    }

    deinit { listener.cancel() }
    func url(_ host: String) -> String { "http://\(host):\(port)/" }
}
