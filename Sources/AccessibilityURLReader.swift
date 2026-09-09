import ApplicationServices
import Foundation

// Pure retry policy kept separate from Dispatch so its timing and bound can be
// unit-tested. Total rapid-retry window: 750ms; afterward normal polling wins.
struct AccessibilityReadinessRetrySchedule {
    static let delays: [TimeInterval] = [0.05, 0.10, 0.20, 0.40]
    private(set) var attemptsIssued = 0

    mutating func takeNextDelay() -> TimeInterval? {
        guard attemptsIssued < Self.delays.count else { return nil }
        let delay = Self.delays[attemptsIssued]
        attemptsIssued += 1
        return delay
    }

    mutating func reset() {
        attemptsIssued = 0
    }
}

// An AXWebArea is safe to retain only after it identifies an actual tab. Gecko
// can leave browser-chrome elements alive after a startup prompt is dismissed;
// their AXURL continues to read successfully even though the selected page is
// now represented by a different element. Keeping such an element makes the
// stale state permanent until Firefox loses focus and TabMemory clears its AX
// cache. This pure policy is separate so that exact lifecycle is regression-
// tested without requiring a live browser.
struct AccessibilityURLCachePolicy {
    static func shouldCache(_ result: BrowserURLReader.ReadResult) -> Bool {
        switch BrowserURLReader.state(from: result) {
        case .site, .newTab: return true
        case .unreadable: return false
        }
    }
}

struct AccessibilityWebAreaCandidateFacts {
    let containsFocus: Bool
    let nestingDepth: Int
    let area: CGFloat
    let order: Int
}

// Select the outer page, never an embedded frame. Gecko exposes iframe/widget
// documents as nested AXWebAreas (Firefox Home currently includes one for a
// remote content card). During cold launch neither area is focused and the outer
// page can temporarily report 0x0 while the child already has a size, so the old
// largest-area fallback could identify the child service as the active site.
enum AccessibilityWebAreaSelection {
    static func preferredIndex(in candidates: [AccessibilityWebAreaCandidateFacts]) -> Int? {
        candidates.indices.min { lhsIndex, rhsIndex in
            let lhs = candidates[lhsIndex]
            let rhs = candidates[rhsIndex]
            if lhs.containsFocus != rhs.containsFocus { return lhs.containsFocus }
            if lhs.nestingDepth != rhs.nestingDepth { return lhs.nestingDepth < rhs.nestingDepth }
            if lhs.area != rhs.area { return lhs.area > rhs.area }
            return lhs.order < rhs.order
        }
    }
}

// Firefox and Gecko forks do not publish AppleScript tab vocabulary, but their
// selected content is available through the standard macOS Accessibility tree.
// Current Gecko activates that tree when an AT reads the application AXRole;
// without that read a Firefox window contains only a few chrome nodes and no
// AXWebArea. Live probes against Firefox 155 and Zen 1.22b found the selected
// page at depth 4–5, with AXURL returned as NSURL. Cold bounded walks measured
// roughly 20–45 ms and cached AXURL reads about 0.02 ms.
//
// A failed walk/read remains `.failed`: treating a transient AX failure as a
// blank tab would replace the remembered site. Only a web area that was found
// but explicitly has no URL is `.blank`.
enum AccessibilityURLReader {

    private struct CachedArea {
        let window: AXUIElement
        let webArea: AXUIElement
    }

    private struct QueueNode {
        let element: AXUIElement
        let depth: Int
        let containingAreas: [Int]
    }

    private struct Candidate {
        let element: AXUIElement
        var containsFocus: Bool
        let nestingDepth: Int
        let order: Int
    }

    private enum URLAttempt {
        case result(BrowserURLReader.ReadResult)
        case invalidElement
        case unavailable
    }

    private static let maxDepth = 12
    private static let maxNodes = 400
    private static var cache: [pid_t: CachedArea] = [:]
    // A PID belongs here only after we have actually read a usable web area.
    // Merely asking Gecko for AXRole is not proof that its asynchronously-built
    // accessibility tree is ready. Caching that early attempt caused every later
    // poll to skip the activation request until the user left and re-entered
    // Firefox.
    private static var readyPIDs = Set<pid_t>()

    static func read(pid: pid_t) -> BrowserURLReader.ReadResult {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        requestTreeActivationIfNeeded(app: app, pid: pid)

        guard let window = elementAttribute(app, kAXFocusedWindowAttribute) else {
            markTreeNotReady(pid: pid)
            return .failed
        }

        // Some non-scriptable browsers expose a URL/document directly on the
        // focused window. Gecko currently does not, so unsupported attributes
        // fall through to the web-area walk.
        for attribute in [kAXURLAttribute, kAXDocumentAttribute] {
            if case .result(let result) = urlAttempt(window, attribute, noValueIsBlank: false) {
                if AccessibilityURLCachePolicy.shouldCache(result) {
                    readyPIDs.insert(pid)
                    return result
                }
                // A window-level browser-chrome URL is not the selected tab.
                // Continue into the web-area search instead of declaring the
                // accessibility tree ready.
                markTreeNotReady(pid: pid)
            }
        }

        if let cached = cache[pid], CFEqual(cached.window, window) {
            switch urlAttempt(cached.webArea, kAXURLAttribute, noValueIsBlank: true) {
            case .result(let result):
                if AccessibilityURLCachePolicy.shouldCache(result) {
                    readyPIDs.insert(pid)
                    return result
                }
                // A successful read is not enough: Firefox browser chrome has
                // a URL too, and its dismissed prompt element can stay readable
                // forever. Discard it and walk the current window again.
                markTreeNotReady(pid: pid)
                requestTreeActivationIfNeeded(app: app, pid: pid)
            case .invalidElement, .unavailable:
                // Gecko can replace its web area while leaving the old AX
                // element technically alive but temporarily URL-less. Keeping
                // that element cached made the failure permanent. Rediscover it
                // now and make the tree activation request retryable.
                markTreeNotReady(pid: pid)
                requestTreeActivationIfNeeded(app: app, pid: pid)
            }
        } else {
            cache[pid] = nil
        }

        guard let area = findActiveWebArea(in: window, app: app) else {
            markTreeNotReady(pid: pid)
            return .failed
        }
        cache[pid] = CachedArea(window: window, webArea: area)
        switch urlAttempt(area, kAXURLAttribute, noValueIsBlank: true) {
        case .result(let result):
            guard AccessibilityURLCachePolicy.shouldCache(result) else {
                markTreeNotReady(pid: pid)
                return .failed
            }
            readyPIDs.insert(pid)
            return result
        case .invalidElement, .unavailable:
            markTreeNotReady(pid: pid)
            return .failed
        }
    }

    static func clear(pid: pid_t) {
        cache[pid] = nil
    }

    static func forget(pid: pid_t) {
        cache[pid] = nil
        readyPIDs.remove(pid)
    }

    private static func requestTreeActivationIfNeeded(app: AXUIElement, pid: pid_t) {
        guard !readyPIDs.contains(pid) else { return }
        var ignored: CFTypeRef?
        // GeckoNSApplication's accessibilityRole implementation enables its
        // native tree (Mozilla bug 1845364). The request can arrive before
        // Firefox is ready; do not cache the attempt itself. A subsequent poll
        // must issue it again until a usable web area proves the tree is live.
        _ = AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &ignored)
    }

    private static func markTreeNotReady(pid: pid_t) {
        cache[pid] = nil
        readyPIDs.remove(pid)
    }

    private static func findActiveWebArea(in window: AXUIElement,
                                          app: AXUIElement) -> AXUIElement? {
        let focused = elementAttribute(app, kAXFocusedUIElementAttribute)
        var queue = [QueueNode(element: window, depth: 0, containingAreas: [])]
        var cursor = 0
        var candidates: [Candidate] = []

        while cursor < queue.count && cursor < maxNodes {
            let node = queue[cursor]
            cursor += 1
            var containingAreas = node.containingAreas

            if stringAttribute(node.element, kAXRoleAttribute) == "AXWebArea" {
                let index = candidates.count
                candidates.append(Candidate(element: node.element,
                                            containsFocus: false,
                                            nestingDepth: containingAreas.count,
                                            order: index))
                containingAreas.append(index)
            }
            if let focused, CFEqual(node.element, focused) {
                // A focused node inside an iframe belongs to both the embedded
                // AXWebArea and its outer tab. Mark the full ancestry; ranking
                // then deliberately prefers the outermost focused page.
                for index in containingAreas {
                    candidates[index].containsFocus = true
                }
            }

            guard node.depth < maxDepth else { continue }
            for child in elementsAttribute(node.element, kAXChildrenAttribute)
                where queue.count < maxNodes {
                queue.append(QueueNode(element: child,
                                       depth: node.depth + 1,
                                       containingAreas: containingAreas))
            }
        }

        let facts = candidates.map {
            AccessibilityWebAreaCandidateFacts(containsFocus: $0.containsFocus,
                                               nestingDepth: $0.nestingDepth,
                                               area: area(of: $0.element),
                                               order: $0.order)
        }
        guard let index = AccessibilityWebAreaSelection.preferredIndex(in: facts) else { return nil }
        return candidates[index].element
    }

    private static func urlAttempt(_ element: AXUIElement,
                                   _ attribute: String,
                                   noValueIsBlank: Bool) -> URLAttempt {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        if error == .invalidUIElement { return .invalidElement }
        if error == .noValue {
            return noValueIsBlank ? .result(.blank) : .unavailable
        }
        guard error == .success, let raw else { return .unavailable }

        let value: String?
        if CFGetTypeID(raw) == CFURLGetTypeID() {
            value = ((raw as! CFURL) as URL).absoluteString
        } else {
            value = raw as? String
        }
        guard let value else { return .unavailable }
        return .result(value.isEmpty ? .blank : .value(value))
    }

    private static func elementAttribute(_ element: AXUIElement,
                                         _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func elementsAttribute(_ element: AXUIElement,
                                          _ attribute: String) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    private static func stringAttribute(_ element: AXUIElement,
                                        _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw as? String
    }

    private static func area(of element: AXUIElement) -> CGFloat {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return 0 }
        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return 0 }
        return size.width * size.height
    }
}
