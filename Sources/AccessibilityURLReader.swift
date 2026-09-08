import ApplicationServices
import Foundation

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
        let containingArea: Int?
    }

    private struct Candidate {
        let element: AXUIElement
        var containsFocus: Bool
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
    private static var activatedPIDs = Set<pid_t>()

    static func read(pid: pid_t) -> BrowserURLReader.ReadResult {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        activateTreeIfNeeded(app: app, pid: pid)

        guard let window = elementAttribute(app, kAXFocusedWindowAttribute) else {
            cache[pid] = nil
            return .failed
        }

        // Some non-scriptable browsers expose a URL/document directly on the
        // focused window. Gecko currently does not, so unsupported attributes
        // fall through to the web-area walk.
        for attribute in [kAXURLAttribute, kAXDocumentAttribute] {
            if case .result(let result) = urlAttempt(window, attribute, noValueIsBlank: false) {
                return result
            }
        }

        if let cached = cache[pid], CFEqual(cached.window, window) {
            switch urlAttempt(cached.webArea, kAXURLAttribute, noValueIsBlank: true) {
            case .result(let result): return result
            case .invalidElement: cache[pid] = nil
            case .unavailable: return .failed
            }
        } else {
            cache[pid] = nil
        }

        guard let area = findActiveWebArea(in: window, app: app) else { return .failed }
        cache[pid] = CachedArea(window: window, webArea: area)
        switch urlAttempt(area, kAXURLAttribute, noValueIsBlank: true) {
        case .result(let result): return result
        case .invalidElement, .unavailable:
            cache[pid] = nil
            return .failed
        }
    }

    static func clear(pid: pid_t) {
        cache[pid] = nil
    }

    static func forget(pid: pid_t) {
        cache[pid] = nil
        activatedPIDs.remove(pid)
    }

    private static func activateTreeIfNeeded(app: AXUIElement, pid: pid_t) {
        guard !activatedPIDs.contains(pid) else { return }
        var ignored: CFTypeRef?
        // GeckoNSApplication's accessibilityRole implementation enables its
        // native tree (Mozilla bug 1845364). Other browsers simply answer role.
        _ = AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &ignored)
        activatedPIDs.insert(pid)
    }

    private static func findActiveWebArea(in window: AXUIElement,
                                          app: AXUIElement) -> AXUIElement? {
        let focused = elementAttribute(app, kAXFocusedUIElementAttribute)
        var queue = [QueueNode(element: window, depth: 0, containingArea: nil)]
        var cursor = 0
        var candidates: [Candidate] = []

        while cursor < queue.count && cursor < maxNodes {
            let node = queue[cursor]
            cursor += 1
            var containingArea = node.containingArea

            if stringAttribute(node.element, kAXRoleAttribute) == "AXWebArea" {
                containingArea = candidates.count
                candidates.append(Candidate(element: node.element,
                                            containsFocus: false,
                                            order: candidates.count))
            }
            if let focused, let index = containingArea, CFEqual(node.element, focused) {
                candidates[index].containsFocus = true
            }

            guard node.depth < maxDepth else { continue }
            for child in elementsAttribute(node.element, kAXChildrenAttribute)
                where queue.count < maxNodes {
                queue.append(QueueNode(element: child,
                                       depth: node.depth + 1,
                                       containingArea: containingArea))
            }
        }

        if let focusedArea = candidates.first(where: \.containsFocus) { return focusedArea.element }
        return candidates.max {
            let lhs = area(of: $0.element)
            let rhs = area(of: $1.element)
            if lhs == rhs { return $0.order > $1.order }
            return lhs < rhs
        }?.element
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
