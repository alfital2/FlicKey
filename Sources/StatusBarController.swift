import AppKit

// Owns the menu bar NSStatusItem and its menu. The menu shows the current
// browser site and lets the user pin its input language (English / Hebrew).
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let tabMemory: TabMemory
    private let inputMonitor = InputSourceMonitor()
    private lazy var settings = SettingsWindowController()
    private lazy var autoSwitchGuide = AutoSwitchGuideController()

    init(tabMemory: TabMemory) {
        self.tabMemory = tabMemory
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.setAccessibilityIdentifier("flickeyStatusItem")

        let menu = NSMenu()
        menu.delegate = self // rebuilt on each open so the site section is current
        statusItem.menu = menu

        // Show the active input language and keep it in sync (input changes and
        // when the user picks a different menu-bar icon style in Settings).
        inputMonitor.onChange = { [weak self] in self?.updateInputIndicator() }
        inputMonitor.start()
        NotificationCenter.default.addObserver(forName: .menuBarIconStyleChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.updateInputIndicator()
        }
        updateInputIndicator()
    }

    // Menu-bar item doubles as a live input-language indicator (EN / HE / …),
    // drawn in the user's chosen style (brand gradient / monochrome / per-language).
    private func updateInputIndicator() {
        guard let button = statusItem.button else { return }
        let code = InputSourceManager.currentSourceCode()
        button.title = ""
        button.setAccessibilityLabel("FlicKey input \(code)")
        button.setAccessibilityValue(code)
        button.image = MenuBarIcon.badge(code: code,
                                         sourceID: InputSourceManager.currentSourceID() ?? "",
                                         style: MenuBarIcon.style)
    }

    // MARK: - Menu (rebuilt each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addAccessibilityWarningIfNeeded(to: menu)
        addAutoSwitchWarningIfNeeded(to: menu)
        addSiteSection(to: menu)

        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
    }

    private func addAccessibilityWarningIfNeeded(to menu: NSMenu) {
        guard !AccessibilityAccess.isTrusted else { return }
        let item = NSMenuItem(title: "⚠️ Accessibility access required…",
                              action: #selector(openAccessibilitySettings), keyEquivalent: "")
        item.target = self
        item.toolTip = "FlicKey cannot monitor typing or edit text until Accessibility access is enabled."
        menu.addItem(item)
        menu.addItem(.separator())
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityAccess.openSettings()
    }

    // Warn when macOS's "Automatically switch to a document's input source" is
    // on — it fights per-site memory. Clicking opens the relevant settings.
    private func addAutoSwitchWarningIfNeeded(to menu: NSMenu) {
        guard OSAutoSwitch.isEnabled() else { return }
        let item = NSMenuItem(title: "⚠️ Disable macOS auto-switch…",
                              action: #selector(openInputSourceSettings), keyEquivalent: "")
        item.target = self
        item.toolTip = "macOS “Automatically switch to a document’s input source” is on and "
            + "overrides FlicKey’s per-site memory. Click to open Keyboard settings, then "
            + "Input Sources ▸ Edit… and turn it off."
        menu.addItem(item)
        menu.addItem(.separator())
    }

    @objc private func openInputSourceSettings() {
        OSAutoSwitch.openKeyboardSettings()
        autoSwitchGuide.present()
    }

    private func addSiteSection(to menu: NSMenu) {
        guard let name = tabMemory.activeSiteDisplayName else {
            let header = NSMenuItem(title: "No browser tab active", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
            return
        }

        let header = NSMenuItem(title: "Site: \(name)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let pinned = tabMemory.pinnedSourceID()
        for source in InputSourceCatalog.enabledSources() {
            let item = NSMenuItem(title: source.localizedName,
                                  action: #selector(pinSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = (pinned == source.id) ? .on : .off
            menu.addItem(item)
        }

        if pinned != nil {
            let none = NSMenuItem(title: "No rule for \(name)",
                                  action: #selector(unpinSite), keyEquivalent: "")
            none.target = self
            menu.addItem(none)
        }

        menu.addItem(.separator())
    }

    // MARK: - Actions

    @objc private func pinSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        tabMemory.pin(id)
    }

    @objc private func unpinSite() { tabMemory.pin(nil) }

    @objc private func showSettings() { settings.present() }

    // Test hook (used by the UI tests via a launch argument).
    func presentSettingsForTesting() { settings.present() }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
