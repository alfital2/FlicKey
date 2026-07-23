#!/usr/bin/env swift
//
// ax-focus-probe.swift — de-risks the "event-driven focus watcher" fix.
//
// Question we're answering:
//   When a BACKGROUND app (e.g. Ghostty) summons a non-activating NSPanel
//   (the quick terminal) and that panel grabs the keyboard, does the app's
//   AX element post a focus notification? And does the system-wide AX focused
//   application reflect that app even though it never became frontmost?
//
//   • If notifications fire        → the event-driven FocusWatcher is viable.
//   • If only the [focus] line moves → only the bounded-poll fallback works.
//   • If neither sees Ghostty       → AX can't see the panel at all; rethink.
//
// HOW TO RUN
//   swift scripts/ax-focus-probe.swift            # defaults to "Ghostty"
//   swift scripts/ax-focus-probe.swift Alfred     # or any other app name
//
// PERMISSION: the TERMINAL APP you run this from must have Accessibility
//   access (System Settings ▸ Privacy & Security ▸ Accessibility). A CLI tool
//   inherits AX trust from its responsible app, i.e. your terminal. If it
//   prints "NOT trusted", grant the terminal, then re-run.
//
// TEST STEPS once it's running:
//   1. Click another app so Ghostty is in the BACKGROUND.
//   2. Press your quick-terminal shortcut (e.g. option+/) and type a key.
//   3. Watch the log. Note which [event] lines fire and whether the [focus]
//      line flips to Ghostty WITHOUT a normal app activation.
//   Ctrl-C to quit.

import AppKit
import ApplicationServices

// MARK: - Helpers

func name(forPID pid: pid_t) -> String {
    NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
}

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

// The pid that AX considers to currently own the keyboard, via the system-wide
// element. This is what a poll-based fallback would read; it also follows
// non-activating panels, unlike NSWorkspace.frontmostApplication.
func systemFocusedPID() -> pid_t? {
    let sys = AXUIElementCreateSystemWide()
    // Prefer the focused UI element (most precise), fall back to focused app.
    for attr in [kAXFocusedUIElementAttribute, kAXFocusedApplicationAttribute] {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(sys, attr as CFString, &ref) == .success,
           let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            var pid: pid_t = 0
            if AXUIElementGetPid(ref as! AXUIElement, &pid) == .success, pid != 0 {
                return pid
            }
        }
    }
    return nil
}

func frontmostLabel() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "none" }
    return "\(app.localizedName ?? "?")(\(app.processIdentifier))"
}

func focusLabel() -> String {
    guard let pid = systemFocusedPID() else { return "none" }
    return "\(name(forPID: pid))(\(pid))"
}

// MARK: - Probe

final class Probe {
    let pid: pid_t
    let targetName: String
    private let element: AXUIElement
    private var observer: AXObserver?
    private var lastFocusPID: pid_t?

    // Every notification we want to know about. Focus-relevant ones first, then
    // DISMISS candidates (does closing the panel destroy/miniaturize its window?).
    let notifications: [String] = [
        kAXFocusedUIElementChangedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXWindowCreatedNotification as String,
        kAXApplicationActivatedNotification as String,
        kAXApplicationDeactivatedNotification as String,
        kAXApplicationShownNotification as String,
        kAXApplicationHiddenNotification as String,
        // Dismiss candidates:
        kAXUIElementDestroyedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
    ]

    init(pid: pid_t, name: String) {
        self.pid = pid
        self.targetName = name
        self.element = AXUIElementCreateApplication(pid)
    }

    func start() {
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<Probe>.fromOpaque(refcon).takeUnretainedValue()
            me.event(notification as String)
        }

        var obs: AXObserver?
        let created = AXObserverCreate(pid, callback, &obs)
        guard created == .success, let obs else {
            print("‼️  AXObserverCreate failed: \(created.rawValue)")
            exit(1)
        }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Register each notification on the APP element and report which the app
        // actually supports (some apps don't emit all of them).
        for n in notifications {
            let r = AXObserverAddNotification(obs, element, n as CFString, refcon)
            print("  register \(short(n)) on \(targetName) → \(axResult(r))")
        }

        // Also TRY the system-wide element, to record whether it can be observed
        // directly (expected: unsupported — you must observe per app).
        let sys = AXUIElementCreateSystemWide()
        let sysR = AXObserverAddNotification(obs, sys, kAXFocusedUIElementChangedNotification as CFString, refcon)
        print("  register FocusedUIElementChanged on <system-wide> → \(axResult(sysR))")

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

        // Diagnostic only: a light timer prints a [focus] line ONLY when the AX
        // focused pid actually changes (deduped — it's quiet otherwise). This
        // measures the poll-fallback's viability without spamming output.
        lastFocusPID = systemFocusedPID()
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkFocus()
        }

        print("\nWatching \(targetName) (pid \(pid)). Background it, then summon the panel.\n" +
              "Lines: [event] = AX notification fired · [focus] = AX keyboard-owner changed\n" +
              "Ctrl-C to quit.\n")
        print("[focus] start  → focus=\(focusLabel())  frontmost=\(frontmostLabel())")
    }

    private func event(_ notification: String) {
        print("[event] \(stamp())  \(short(notification))" +
              "  | \(ownFocusDesc())  | sysfocus=\(focusLabel())  frontmost=\(frontmostLabel())")
    }

    // The GATE candidate: read the TARGET app's OWN focused UI element + focused
    // window (not the system-wide element, which returned none). If this reliably
    // reads non-nil when the panel opens and nil/different when it closes, the
    // FocusWatcher can use it to suppress dismiss-flicker. Read from the app's own
    // element, which answers about itself.
    private func ownFocusDesc() -> String {
        var elDesc = "elem=?"
        var elRef: CFTypeRef?
        let er = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &elRef)
        if er == .success, let elRef, CFGetTypeID(elRef) == AXUIElementGetTypeID() {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elRef as! AXUIElement, kAXRoleAttribute as CFString, &roleRef)
            elDesc = "elem=\(roleRef as? String ?? "set")"
        } else {
            elDesc = "elem=nil(\(axResult(er)))"
        }

        var winDesc = "win=?"
        var winRef: CFTypeRef?
        let wr = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &winRef)
        if wr == .success, let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(winRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
            let t = (titleRef as? String) ?? ""
            winDesc = "win=set(\(t.prefix(20)))"
        } else {
            winDesc = "win=nil(\(axResult(wr)))"
        }
        return "\(elDesc) \(winDesc)"
    }

    private func checkFocus() {
        let now = systemFocusedPID()
        if now != lastFocusPID {
            lastFocusPID = now
            let tag = now == pid ? "  ⬅︎ TARGET now owns keyboard" : ""
            print("[focus] \(stamp())  → focus=\(focusLabel())  frontmost=\(frontmostLabel())\(tag)")
        }
    }
}

// MARK: - Formatting

func short(_ n: String) -> String { n.replacingOccurrences(of: "AX", with: "") }

func axResult(_ r: AXError) -> String {
    switch r {
    case .success: return "ok"
    case .notificationUnsupported: return "UNSUPPORTED"
    case .notificationAlreadyRegistered: return "already-registered"
    case .cannotComplete: return "cannot-complete"
    case .notImplemented: return "not-implemented"
    case .invalidUIElement: return "invalid-element"
    default: return "err(\(r.rawValue))"
    }
}

// MARK: - Main

// Unbuffer stdout — otherwise, when output is redirected to a file (not a TTY),
// print() is block-buffered and nothing appears until the buffer fills, which
// never happens because we then sit in the run loop forever.
setvbuf(stdout, nil, _IONBF, 0)

let targetName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Ghostty"

// Require Accessibility (prompts, listing the responsible terminal app).
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
if !trusted {
    print("⚠️  This process is NOT trusted for Accessibility.\n" +
          "   Grant your TERMINAL app in System Settings ▸ Privacy & Security ▸\n" +
          "   Accessibility, then re-run. (A prompt may have just appeared.)")
    exit(2)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    ($0.localizedName?.caseInsensitiveCompare(targetName) == .orderedSame)
        || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(targetName) == true)
}) else {
    print("Couldn't find a running app named \"\(targetName)\". Is it launched?")
    exit(3)
}

print("FlicKey AX focus probe — target: \(app.localizedName ?? targetName) " +
      "(\(app.bundleIdentifier ?? "?"), pid \(app.processIdentifier))\n")

let probe = Probe(pid: app.processIdentifier, name: app.localizedName ?? targetName)
probe.start()
RunLoop.main.run()
