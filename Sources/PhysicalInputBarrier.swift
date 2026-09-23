import AppKit
import CoreGraphics

// A passive tap except during the brief replacement transaction. AX calls and
// spell checking stay on the main thread; the tap callback only queues/copies
// events, acknowledges generated keys, and replays queued physical input.
final class PhysicalInputBarrier {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var workerDone: DispatchSemaphore?
    private var held = InputHoldQueue<CGEvent>()
    private var latestInput: UInt64 = 0
    private var replayLayout: LayoutMap?
    private var receiptToken: Int64 = 0
    private var receiptRemaining = 0
    private var receipt: DispatchSemaphore?
    private var draining = false
    private static let replayTag: Int64 = 0x464C5245504C4159
    private let replaySource: CGEventSource?

    init() {
        replaySource = CGEventSource(stateID: .privateState)
        replaySource?.userData = Self.replayTag
    }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    @discardableResult
    func start() -> Bool {
        guard replaySource != nil else { return false }
        if isActive { return true }
        stop()
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        lock.lock(); workerDone = done; lock.unlock()
        Thread.detachNewThread { [self] in
            defer { done.signal() }
            let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
                .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                .otherMouseDown, .otherMouseUp, .scrollWheel,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            guard let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, info in
                    guard let info else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<PhysicalInputBarrier>.fromOpaque(info)
                        .takeUnretainedValue().handle(type, event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            else { ready.signal(); return }
            let loop = CFRunLoopGetCurrent()!
            lock.lock(); tap = created; runLoop = loop; lock.unlock()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(created)
        }
        ready.wait()
        return isActive
    }

    func stop() {
        lock.lock()
        post(held.stop())
        receipt?.signal()
        receipt = nil
        receiptRemaining = 0
        let loop = runLoop
        let oldTap = tap
        let done = workerDone
        tap = nil; runLoop = nil; workerDone = nil
        latestInput = 0; draining = false
        lock.unlock()
        if let oldTap { CGEvent.tapEnable(tap: oldTap, enable: false) }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
        done?.wait()
    }

    // Reject a stale tracker snapshot: a physical key already seen by this
    // pre-delivery tap but not yet by NSEvent must not be swallowed as a tail.
    func begin(after observedTimestamp: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let tap, CGEvent.tapIsEnabled(tap: tap), !held.isHolding,
              observedTimestamp != 0, latestInput == observedTimestamp else { return false }
        replayLayout = nil
        draining = false
        return held.begin()
    }

    // Register BEFORE posting the first generated key. The main thread may
    // then wait without blocking the tap's independent run loop.
    func expectSynthetic(token: Int64, count: Int) {
        lock.lock(); defer { lock.unlock() }
        receiptToken = token
        receiptRemaining = count
        receipt = DispatchSemaphore(value: 0)
    }

    func waitForSynthetic(timeout: TimeInterval) -> Bool {
        lock.lock(); let semaphore = receipt; lock.unlock()
        guard let semaphore else { return false }
        let arrived = semaphore.wait(timeout: .now() + timeout) == .success
        lock.lock()
        let complete = arrived && receiptRemaining == 0
        receipt = nil
        receiptRemaining = 0
        lock.unlock()
        return complete
    }

    func finish(layout: LayoutMap? = nil) {
        lock.lock(); defer { lock.unlock() }
        replayLayout = layout
        draining = true
        post(held.drain())
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock(); defer { lock.unlock() }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            latestInput = 0
            receipt?.signal()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if draining { post(held.stop()); draining = false }
            return Unmanaged.passUnretained(event)
        }
        let tag = event.getIntegerValueField(.eventSourceUserData)
        if tag == Self.replayTag {
            if type == .keyDown { latestInput = event.timestamp }
            post(held.didReplay())
            return Unmanaged.passUnretained(event)
        }
        if SyntheticEventMarker.isMarked(event) {
            if tag == receiptToken && receiptRemaining > 0 {
                receiptRemaining -= 1
                if receiptRemaining == 0 { receipt?.signal() }
            }
            return Unmanaged.passUnretained(event)
        }
        if held.isHolding, let copy = event.copy(), held.capture(copy) { return nil }
        if type == .keyDown { latestInput = event.timestamp }
        else if type != .keyUp && type != .flagsChanged { latestInput = 0 }
        return Unmanaged.passUnretained(event)
    }

    // Called under lock. Replayed physical keys must be observed by the usual
    // tracker; only FlicKey's generated replacement keys are ignored.
    private func post(_ events: [CGEvent]) {
        for event in events {
            if let map = replayLayout, event.type == .keyDown || event.type == .keyUp,
               event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
               let output = map.character(forKeyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                              shift: event.flags.contains(.maskShift),
                                              capsLock: event.flags.contains(.maskAlphaShift)) {
                let units = Array(output.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            if let replaySource { SyntheticEventMarker.retag(event, using: replaySource) }
            event.post(tap: .cgSessionEventTap)
        }
    }
}
