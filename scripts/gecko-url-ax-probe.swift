#!/usr/bin/env swift
// Probe Gecko's Accessibility tree before relying on it for active-tab URLs.
// Launch Firefox and/or Zen, focus a real page, then run this script. It reports
// the focused window's direct URL attributes, every reachable AXWebArea, the
// role chain/depth, value type, focus relationship, size, and read timing.
import AppKit
import ApplicationServices

private let maxDepth = 12
private let maxNodes = 400

private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
        return nil
    }
    return result
}

private func string(_ value: CFTypeRef?) -> String? {
    guard let value else { return nil }
    if let text = value as? String { return text }
    if CFGetTypeID(value) == CFURLGetTypeID() {
        return ((value as! CFURL) as URL).absoluteString
    }
    return "\(value)"
}

private func role(_ element: AXUIElement) -> String {
    string(value(element, kAXRoleAttribute)) ?? "?"
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

private func size(_ element: AXUIElement) -> CGSize? {
    guard let raw = value(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
        return nil
    }
    var result = CGSize.zero
    guard AXValueGetValue(raw as! AXValue, .cgSize, &result) else { return nil }
    return result
}

private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
    CFEqual(lhs, rhs)
}

private func contains(_ root: AXUIElement, target: AXUIElement, budget: inout Int) -> Bool {
    guard budget > 0 else { return false }
    budget -= 1
    if sameElement(root, target) { return true }
    for child in children(root) where contains(child, target: target, budget: &budget) {
        return true
    }
    return false
}

private struct FoundWebArea {
    let element: AXUIElement
    let depth: Int
    let roles: [String]
}

private func webAreas(from window: AXUIElement) -> (areas: [FoundWebArea], visited: Int) {
    var queue: [(AXUIElement, Int, [String])] = [(window, 0, [role(window)])]
    var cursor = 0
    var found: [FoundWebArea] = []
    while cursor < queue.count && cursor < maxNodes {
        let (element, depth, roles) = queue[cursor]
        cursor += 1
        if role(element) == "AXWebArea" {
            found.append(FoundWebArea(element: element, depth: depth, roles: roles))
        }
        guard depth < maxDepth else { continue }
        for child in children(element) where queue.count < maxNodes {
            queue.append((child, depth + 1, roles + [role(child)]))
        }
    }
    return (found, cursor)
}

private func probe(bundleID: String, label: String) {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleID
    }) else {
        print("\(label): not running")
        return
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 1.0)
    // Current Firefox enables its native a11y tree when an AT asks for the
    // application's role (Mozilla bug 1845364 / GeckoNSApplication+a11y).
    let appRole = string(value(appElement, kAXRoleAttribute)) ?? "nil"
    Thread.sleep(forTimeInterval: 0.25)
    var windowRef: CFTypeRef?
    let windowError = AXUIElementCopyAttributeValue(
        appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
    guard windowError == .success,
          let windowRef,
          CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
        print("\(label): no focused window (AX error \(windowError.rawValue))")
        return
    }
    let window = windowRef as! AXUIElement
    let focused = value(appElement, kAXFocusedUIElementAttribute).flatMap { raw -> AXUIElement? in
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    print("\n=== \(label) (\(bundleID), pid \(app.processIdentifier)) ===")
    print("application role (activation read): \(appRole)")
    print("window title:    \(string(value(window, kAXTitleAttribute)) ?? "nil")")
    print("window document: \(string(value(window, kAXDocumentAttribute)) ?? "nil")")
    print("window URL:      \(string(value(window, kAXURLAttribute)) ?? "nil")")

    let started = CFAbsoluteTimeGetCurrent()
    let scan = webAreas(from: window)
    let elapsedMS = (CFAbsoluteTimeGetCurrent() - started) * 1_000
    print("BFS: \(scan.visited) nodes, \(scan.areas.count) web areas, \(String(format: "%.2f", elapsedMS)) ms")

    for (index, area) in scan.areas.enumerated() {
        var focusBudget = maxNodes
        let hasFocus = focused.map { contains(area.element, target: $0, budget: &focusBudget) } ?? false
        let dimensions = size(area.element).map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
        let rawURL = value(area.element, kAXURLAttribute)
        let valueType = rawURL.map { String(describing: Swift.type(of: $0)) } ?? "nil"
        print("webArea[\(index)]:")
        print("  depth/roles: \(area.depth) / \(area.roles.joined(separator: " > "))")
        print("  URL:         \(string(rawURL) ?? "nil") (\(valueType))")
        print("  focused:     \(hasFocus)")
        print("  size:        \(dimensions)")
    }

    if let first = scan.areas.first {
        let warmStarted = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 { _ = value(first.element, kAXURLAttribute) }
        let warmMS = (CFAbsoluteTimeGetCurrent() - warmStarted) * 10
        print("warm AXURL read average: \(String(format: "%.3f", warmMS)) ms")
    }
}

print("AX trusted: \(AXIsProcessTrusted())")
probe(bundleID: "org.mozilla.firefox", label: "Firefox")
probe(bundleID: "app.zen-browser.zen", label: "Zen")
probe(bundleID: "org.chromium.Chromium", label: "Chromium")
