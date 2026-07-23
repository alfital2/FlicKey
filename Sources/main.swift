import AppKit

// AppKit entry point (no SwiftUI @main lifecycle).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar agent, no Dock icon
app.run()
