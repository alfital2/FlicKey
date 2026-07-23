#!/usr/bin/env swift
// Probe: can we read the FOCUSED Safari window's URL via Accessibility (so we
// read the window the user is actually on, not AppleScript's ambiguous "front
// window")? Prints the focused window's AXDocument + lists attributes, for both
// Safari and Chrome if present.
import AppKit
import ApplicationServices

func read(_ el: AXUIElement, _ attr: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return nil }
    if let s = v as? String { return s }
    if CFGetTypeID(v) == CFURLGetTypeID() { return ((v as! CFURL) as URL).absoluteString }
    return "\(v)"
}

func probe(_ bundleID: String, _ label: String) {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
        print("\(label): not running"); return
    }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var winRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
          let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else {
        print("\(label): no focused window"); return
    }
    let win = winRef as! AXUIElement
    print("=== \(label) (pid \(app.processIdentifier)) focused window ===")
    print("  AXTitle:    \(read(win, "AXTitle") ?? "nil")")
    print("  AXDocument: \(read(win, "AXDocument") ?? "nil")")
    print("  AXURL:      \(read(win, "AXURL") ?? "nil")")
    var names: CFArray?
    if AXUIElementCopyAttributeNames(win, &names) == .success, let names = names as? [String] {
        print("  all window attrs: \(names.joined(separator: ", "))")
    }
    // how many windows total + each window's AXDocument (to show they differ)
    var winsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &winsRef) == .success,
       let wins = winsRef as? [AXUIElement] {
        print("  window count: \(wins.count)")
        for (i, w) in wins.enumerated() {
            print("    window[\(i)] AXDocument=\(read(w, "AXDocument") ?? "nil")  title=\(read(w, "AXTitle") ?? "nil")")
        }
    }
}

print("AX trusted: \(AXIsProcessTrusted())\n")
probe("com.apple.Safari", "Safari")
probe("com.google.Chrome", "Chrome")
