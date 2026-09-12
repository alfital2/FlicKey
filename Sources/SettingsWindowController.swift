import AppKit

// One centralized Settings window: a toolbar-tabbed preferences window
// (General · Shortcut · Apps) with SF Symbol icons. Replaces the growing
// menu-bar Settings submenu.
final class SettingsWindowController: NSWindowController {

    private var keyMonitor: Any?

    convenience init() {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar

        // "Sound", not "Sound & Haptics": the long label made its toolbar item
        // visibly wider than every other tab. The pane itself still covers haptics.
        let specs: [(NSViewController, String, String)] = [
            (GeneralSettingsViewController(), "General", "gearshape"),
            (SoundHapticsSettingsViewController(), "Sound", "hand.tap"),
            (ShortcutSettingsViewController(), "Shortcut", "keyboard"),
            (AppsSettingsViewController(), "Apps", "square.grid.2x2"),
            (StatsSettingsViewController(), SwitchStats.total.formatted(), "arrow.left.arrow.right"),
            (ImproveSettingsViewController(), "Improve", "ladybug"),
            (LicenseSettingsViewController(), "Support", "heart"),
        ]
        for (vc, label, symbol) in specs {
            let item = NSTabViewItem(viewController: vc)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "General"
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func present() {
        installWindowKeyShortcuts()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func installWindowKeyShortcuts() {
        guard keyMonitor == nil else { return }
        // LSUIElement apps have no main menu, so neither ⌘W nor the standard
        // Edit shortcuts (⌘X/⌘C/⌘V/⌘A) are wired. Forward them to the first
        // responder ourselves. Match physical key codes, NOT characters, so they
        // work in any keyboard layout (e.g. Hebrew).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let window = self?.window, window.isKeyWindow,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            else { return event }
            // Route an editing action to the field editor; pass the event
            // through unchanged if nothing in the responder chain handles it.
            let dispatch: (String) -> NSEvent? = { selectorName in
                NSApp.sendAction(Selector(selectorName), to: nil, from: nil) ? nil : event
            }
            switch event.keyCode {
            case 13: window.performClose(nil); return nil   // W
            case 0:  return dispatch("selectAll:")          // A
            case 7:  return dispatch("cut:")                // X
            case 8:  return dispatch("copy:")               // C
            case 9:  return dispatch("paste:")              // V
            default: return event
            }
        }
    }
}

// Resizes the window to each pane's preferred size on selection (so the Apps
// tab gets taller), and shows the pane name as the window title.
final class SettingsTabViewController: NSTabViewController {

    // Keep the stats tab's toolbar label (the running total) live: it is set once
    // at construction, so without this a fix landing mid-session left the label
    // stale until relaunch (QA BUG 0.5.0-3).
    private var statsToken: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        statsToken = NotificationCenter.default.addObserver(
            forName: .switchStatsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshStatsLabel()
        }
    }

    deinit {
        if let statsToken { NotificationCenter.default.removeObserver(statsToken) }
    }

    private func refreshStatsLabel() {
        guard let item = tabViewItems.first(where: { $0.viewController is StatsSettingsViewController })
        else { return }
        let total = SwitchStats.total.formatted()
        guard item.label != total else { return }
        item.label = total
        // If the stats tab is frontmost, the window title mirrors the label.
        if tabViewItems.indices.contains(selectedTabViewItemIndex),
           tabViewItems[selectedTabViewItemIndex] === item {
            title = total
        }
    }

    // Set the initial title/size for the first tab, which never fires didSelect.
    override func viewWillAppear() {
        super.viewWillAppear()
        refreshStatsLabel()
        applySelectedTab(animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        applySelectedTab(animated: true)
    }

    private func applySelectedTab(animated: Bool) {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        let item = tabViewItems[selectedTabViewItemIndex]

        // Setting the controller's `title` drives the window title via the
        // contentViewController binding (plain window.title gets overridden).
        title = item.label

        guard let window = view.window else { return }
        let size = item.viewController?.preferredContentSize ?? .zero
        guard size.width > 0, size.height > 0 else { return }

        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - target.height   // keep the title bar anchored
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animated)
    }
}

// MARK: - General
//
// App-level settings only: how FlicKey starts, appears, and updates. The
// sensory settings (clicks, volume, layout cue) live in Sound & Haptics.

final class GeneralSettingsViewController: NSViewController {

    // Short marketing version (e.g. "0.4.5") for the footnote label.
    private var appShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private let launchSwitch = NSSwitch()
    private let autoUpdateSwitch = NSSwitch()
    private let autoCorrectSwitch = NSSwitch()
    private let autoCorrectHealth = NSTextField(wrappingLabelWithString: "")
    private let openAccessibilityButton = NSButton(title: "Open Accessibility Settings…",
                                                   target: nil, action: nil)
    private let iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let blocklist = AutoSwitchBlocklistController()

    override func loadView() {
        for (toggle, action, id) in [
            (launchSwitch, #selector(toggleLaunch), "launchAtLoginSwitch"),
            (autoUpdateSwitch, #selector(toggleAutoUpdate), "autoUpdateSwitch"),
            (autoCorrectSwitch, #selector(toggleAutoCorrect), "autoCorrectSwitch"),
        ] {
            toggle.target = self
            toggle.action = action
            toggle.setAccessibilityIdentifier(id)
        }

        iconPopup.addItems(withTitles: MenuBarIconStyle.allCases.map { $0.displayName })
        iconPopup.target = self; iconPopup.action = #selector(pickIcon)

        let checkNow = NSButton(title: "Check for Updates Now",
                                target: self, action: #selector(checkNow))
        checkNow.bezelStyle = .rounded

        autoCorrectHealth.textColor = .systemOrange
        autoCorrectHealth.isHidden = true
        openAccessibilityButton.target = self
        openAccessibilityButton.action = #selector(openAccessibilitySettings)
        openAccessibilityButton.bezelStyle = .rounded
        openAccessibilityButton.isHidden = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAutoCorrectHealth),
            name: .autoSwitchMonitorHealthChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAutoCorrectHealth),
            name: .accessibilityTrustChanged, object: nil)

        #if DEBUG
        let versionLabel = "FlicKey \(appShortVersion) (QA TEST BUILD — Unlocked)"
        #else
        let versionLabel = "FlicKey \(appShortVersion)"
        #endif

        let cards = [
            settingsCard([settingsRow("Launch FlicKey at login", launchSwitch)]),
            settingsCard([settingsRow("Icon", iconPopup)]),
            settingsCard([settingsRow("Automatically check for updates", autoUpdateSwitch)]),
            settingsCard([settingsRow("Auto-switch when typing the wrong layout  (beta)", autoCorrectSwitch)]),
        ]

        let manageBlocked = NSButton(title: "Manage Blocked Words…",
                                     target: self, action: #selector(manageBlockedWords))
        manageBlocked.bezelStyle = .rounded

        let stack = NSStackView(views: [
            sectionHeader("Startup"), cards[0],
            spacer(6),
            sectionHeader("Typing"), cards[3],
            autoCorrectHealth,
            openAccessibilityButton,
            settingsFootnote("Fixes and switches the layout after you type two words in the wrong keyboard language. Undo the last fix with ⌥⌥ (double-tap Option); undo the same word twice and FlicKey stops auto-switching it."),
            manageBlocked,
            settingsFootnote("Bug reports from Improve add auto-switch details (layouts, working dictionaries, timing), never what you type. FlicKey also shares words it wrongly fixed so it can learn; turn that off in Improve."),
            spacer(6),
            sectionHeader("Menu Bar"), cards[1],
            spacer(6),
            sectionHeader("Updates"), cards[2], checkNow,
            spacer(10),
            settingsFootnote(versionLabel),
        ])
        installSettingsPane(stack, cards: cards)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        autoUpdateSwitch.state = (UITestMode.isActive ? true : Updater.shared.automaticallyChecksForUpdates) ? .on : .off
        autoCorrectSwitch.state = AutoSwitchSettings.isEnabled ? .on : .off
        refreshAutoCorrectHealth()
        if let idx = MenuBarIconStyle.allCases.firstIndex(of: MenuBarIcon.style) {
            iconPopup.selectItem(at: idx)
        }
    }

    @objc private func toggleLaunch() {
        let want = launchSwitch.state == .on
        if !LaunchAtLogin.setEnabled(want) {
            launchSwitch.state = LaunchAtLogin.isEnabled ? .on : .off   // revert on failure
        }
    }

    @objc private func toggleAutoUpdate() {
        guard !UITestMode.isActive else { return }
        Updater.shared.automaticallyChecksForUpdates = (autoUpdateSwitch.state == .on)
    }

    @objc private func toggleAutoCorrect() {
        AutoSwitchSettings.isEnabled = (autoCorrectSwitch.state == .on)
        refreshAutoCorrectHealth()
    }

    @objc private func refreshAutoCorrectHealth() {
        guard AutoSwitchSettings.isEnabled else {
            autoCorrectHealth.isHidden = true
            openAccessibilityButton.isHidden = true
            return
        }
        switch AutoSwitchMonitorHealth.state {
        case .inactive, .available:
            autoCorrectHealth.isHidden = true
            openAccessibilityButton.isHidden = true
        case .unavailable(.accessibilityDenied):
            autoCorrectHealth.stringValue =
                "Auto-fix is paused because FlicKey does not have Accessibility access."
            autoCorrectHealth.isHidden = false
            openAccessibilityButton.isHidden = false
        case .unavailable(.monitorCreationFailed):
            autoCorrectHealth.stringValue =
                "Auto-fix could not start its keyboard monitor. Switch apps to retry, or relaunch FlicKey."
            autoCorrectHealth.isHidden = false
            openAccessibilityButton.isHidden = true
        }
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityAccess.openSettings()
    }

    @objc private func manageBlockedWords() {
        blocklist.present(from: view.window)
    }

    @objc private func pickIcon() {
        let idx = iconPopup.indexOfSelectedItem
        guard MenuBarIconStyle.allCases.indices.contains(idx) else { return }
        MenuBarIcon.style = MenuBarIconStyle.allCases[idx]   // re-renders the menu-bar badge live
    }

    @objc private func checkNow() {
        guard !UITestMode.isActive else { return }
        Updater.shared.checkForUpdates()
    }
}

// MARK: - Sound & Haptics
//
// Every sensory cue FlicKey gives: the conversion click (+ its sound/volume)
// and the layout-switch cue (per-layout haptic/sound taps).

final class SoundHapticsSettingsViewController: NSViewController {

    private let soundSwitch = NSSwitch()
    private let cueHapticSwitch = NSSwitch()
    private let cueSoundSwitch = NSSwitch()
    private let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let volumeControl = NSSegmentedControl()
    private let hapticIntensityControl = NSSegmentedControl()
    // One Off/1/2/3-taps popup per enabled layout, built from the live catalog.
    private var tapRows: [(id: String, code: String?, popup: NSPopUpButton)] = []

    override func loadView() {
        for (toggle, action, id) in [
            (soundSwitch, #selector(toggleSound), "clickSoundSwitch"),
            (cueHapticSwitch, #selector(toggleCueHaptic), "cueHapticSwitch"),
            (cueSoundSwitch, #selector(toggleCueSound), "cueSoundSwitch"),
        ] {
            toggle.target = self
            toggle.action = action
            toggle.setAccessibilityIdentifier(id)
        }

        soundPopup.addItems(withTitles: SoundEffect.options.map { $0.name })
        soundPopup.target = self; soundPopup.action = #selector(pickSound)
        soundPopup.setAccessibilityIdentifier("clickSoundPicker")

        configureVolumeControl()
        configureHapticIntensityControl()

        let cards = [
            settingsCard([
                settingsRow("Play a click when a fix lands", soundSwitch),
                settingsRow("Click sound on layout switch", cueSoundSwitch),
                settingsRow("Sound", soundPopup),
                settingsRow("Volume", volumeControl),
            ]),
            settingsCard([
                settingsRow("Trackpad haptic on layout switch", cueHapticSwitch),
                settingsRow("Intensity", hapticIntensityControl),
            ] + buildTapRows()),
        ]

        let stack = NSStackView(views: [
            sectionHeader("Sound"), cards[0],
            settingsFootnote("Used for both the conversion click and the layout-switch click."),
            spacer(6),
            sectionHeader("Haptics"), cards[1],
            settingsFootnote("Haptics only work when the lid is open."),
            settingsFootnote("Each layout gets its own signal. Up to three taps; more isn’t distinguishable."),
        ])
        installSettingsPane(stack, cards: cards)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        soundSwitch.state = SoundEffect.isEnabled ? .on : .off
        if let idx = SoundEffect.options.firstIndex(where: { $0 == SoundEffect.selected }) {
            soundPopup.selectItem(at: idx)
        }
        volumeControl.selectedSegment = SoundEffect.volumeLevel
        refreshSoundEnablement()
        cueHapticSwitch.state = LayoutCueSettings.hapticEnabled ? .on : .off
        cueSoundSwitch.state = LayoutCueSettings.soundEnabled ? .on : .off
        hapticIntensityControl.selectedSegment = LayoutCueSettings.hapticIntensityLevel
        hapticIntensityControl.isEnabled = LayoutCueSettings.hapticEnabled
        for row in tapRows {
            row.popup.selectItem(at: LayoutCueSettings.tapCount(forSourceID: row.id,
                                                                defaultLanguageCode: row.code))
        }
        refreshCueEnablement()
    }

    // A 3-step Light/Medium/Strong control for the layout-switch haptic. Maps to
    // the OS's actuation IDs; on some (esp. built-in) trackpads the steps feel
    // similar, so it previews on select and defaults to the strongest.
    private func configureHapticIntensityControl() {
        hapticIntensityControl.segmentStyle = .rounded
        hapticIntensityControl.trackingMode = .selectOne
        hapticIntensityControl.segmentCount = LayoutCueSettings.hapticLevels
        for (i, label) in ["Light", "Medium", "Strong"].enumerated() {
            hapticIntensityControl.setLabel(label, forSegment: i)
        }
        hapticIntensityControl.target = self; hapticIntensityControl.action = #selector(pickHapticIntensity)
        hapticIntensityControl.setAccessibilityIdentifier("hapticIntensity")
    }

    // A 4-step speaker control governing every FlicKey click's volume.
    private func configureVolumeControl() {
        volumeControl.segmentStyle = .rounded
        volumeControl.trackingMode = .selectOne
        volumeControl.segmentCount = SoundEffect.volumeLevels
        let symbols = ["speaker.fill", "speaker.wave.1.fill",
                       "speaker.wave.2.fill", "speaker.wave.3.fill"]
        for i in 0..<SoundEffect.volumeLevels {
            volumeControl.setImage(NSImage(systemSymbolName: symbols[i],
                                           accessibilityDescription: "Volume \(i + 1)"), forSegment: i)
            volumeControl.setWidth(34, forSegment: i)
        }
        volumeControl.target = self; volumeControl.action = #selector(pickVolume)
        volumeControl.setAccessibilityIdentifier("clickSoundVolume")
    }

    // One Off/1/2/3-taps row per enabled keyboard layout, read live from the
    // system so it always matches the user's real layouts. Returned as rows (not a
    // card) so they share the Haptics card with the haptic toggle and intensity.
    private func buildTapRows() -> [NSView] {
        tapRows = InputSourceCatalog.enabledSources().map { source in
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["Off", "1 tap", "2 taps", "3 taps"])
            popup.target = self; popup.action = #selector(pickTaps(_:))
            popup.setAccessibilityIdentifier("tapsPopup")
            return (id: source.id, code: source.languageCodes.first, popup: popup)
        }
        guard !tapRows.isEmpty else {
            return [settingsRow("No keyboard layouts found", NSView())]
        }
        return tapRows.map { row in
            settingsRow(InputSourceCatalog.localizedName(for: row.id) ?? row.id, row.popup)
        }
    }

    // The per-layout pickers only matter while some cue output is on.
    private func refreshCueEnablement() {
        let on = LayoutCueSettings.hapticEnabled || LayoutCueSettings.soundEnabled
        tapRows.forEach { $0.popup.isEnabled = on }
    }

    // Sound + volume are shared, so they stay live while EITHER the conversion
    // click or the layout-switch click uses them.
    private func refreshSoundEnablement() {
        let on = SoundEffect.isEnabled || LayoutCueSettings.soundEnabled
        soundPopup.isEnabled = on
        volumeControl.isEnabled = on
    }

    @objc private func toggleSound() {
        let on = soundSwitch.state == .on
        SoundEffect.isEnabled = on
        refreshSoundEnablement()
        if on { SoundEffect.playClick() }   // preview the click when enabling
    }

    @objc private func pickSound() {
        let idx = soundPopup.indexOfSelectedItem
        guard SoundEffect.options.indices.contains(idx) else { return }
        let sound = SoundEffect.options[idx]
        SoundEffect.select(sound)
        SoundEffect.preview(sound)   // hear the choice immediately
    }

    @objc private func pickVolume() {
        SoundEffect.volumeLevel = volumeControl.selectedSegment
        SoundEffect.preview(SoundEffect.selected)   // hear the new level
    }

    @objc private func toggleCueHaptic() {
        let on = cueHapticSwitch.state == .on
        LayoutCueSettings.hapticEnabled = on
        hapticIntensityControl.isEnabled = on
        refreshCueEnablement()
        if on { LayoutCueController.play(count: 1, haptic: true, sound: false) }   // feel it
    }

    @objc private func pickHapticIntensity() {
        LayoutCueSettings.hapticIntensityLevel = hapticIntensityControl.selectedSegment
        LayoutCueController.play(count: 1, haptic: true, sound: false)   // feel the chosen strength
    }

    @objc private func toggleCueSound() {
        let on = cueSoundSwitch.state == .on
        LayoutCueSettings.soundEnabled = on
        refreshCueEnablement()
        refreshSoundEnablement()   // the shared sound picker follows this too
        if on { LayoutCueController.play(count: 1, haptic: false, sound: true) }   // hear it
    }

    @objc private func pickTaps(_ sender: NSPopUpButton) {
        guard let row = tapRows.first(where: { $0.popup === sender }) else { return }
        let count = sender.indexOfSelectedItem   // 0 = Off, 1–3 = taps
        LayoutCueSettings.setTapCount(count, forSourceID: row.id)
        if count > 0 {   // demonstrate the chosen signal
            LayoutCueController.play(count: count,
                                     haptic: LayoutCueSettings.hapticEnabled,
                                     sound: LayoutCueSettings.soundEnabled)
        }
    }
}

// MARK: - Shortcut

final class ShortcutSettingsViewController: NSViewController {

    // Side-by-side presets; the user picks one or records a custom chord.
    private let doubleShiftRadio = NSButton(radioButtonWithTitle: "Double-tap Shift  ⇧⇧",
                                            target: nil, action: nil)
    private let optionTwoRadio = NSButton(radioButtonWithTitle: "Option-2  ⌥2",
                                          target: nil, action: nil)

    private let currentField = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Record Custom Shortcut", target: nil, action: nil)
    private var monitor: Any?
    // Recording exactly while the key monitor is installed; one source of truth.
    private var recording: Bool { monitor != nil }

    override func loadView() {
        let header = sectionHeader("Conversion Shortcut")
        let desc = NSTextField(wrappingLabelWithString:
            "The trigger that fixes text typed in the wrong layout. "
            + "Pick a preset, or record your own.")
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor

        for radio in [doubleShiftRadio, optionTwoRadio] {
            radio.target = self; radio.action = #selector(selectPreset(_:))
        }
        doubleShiftRadio.setAccessibilityIdentifier("triggerDoubleShift")
        optionTwoRadio.setAccessibilityIdentifier("triggerOptionTwo")

        let presets = NSStackView(views: [doubleShiftRadio, optionTwoRadio])
        presets.orientation = .horizontal
        presets.spacing = 18

        currentField.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        currentField.setAccessibilityIdentifier("currentShortcut")

        recordButton.target = self; recordButton.action = #selector(toggleRecord)
        recordButton.bezelStyle = .rounded
        recordButton.setAccessibilityIdentifier("recordShortcut")

        let reset = NSButton(title: "Reset to ⇧⇧", target: self, action: #selector(resetDefault))
        reset.bezelStyle = .rounded
        // Stable hook for UI tests (the glyph in the title mangles the AX label).
        reset.setAccessibilityIdentifier("resetShortcut")

        let buttons = NSStackView(views: [recordButton, reset])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [header, desc, spacer(6), presets, spacer(6),
                                        currentField, spacer(6), buttons])
        installSettingsPane(stack, cards: [], spacing: 10)
    }

    override func viewWillAppear() { super.viewWillAppear(); stopRecording(); refresh() }
    override func viewWillDisappear() { super.viewWillDisappear(); stopRecording() }

    private func refresh() {
        let kind = ShortcutStore.currentKind()
        let isOptionTwo = kind == .chord && ShortcutStore.current() == .default
        doubleShiftRadio.state = kind == .doubleShift ? .on : .off
        optionTwoRadio.state = isOptionTwo ? .on : .off
        currentField.stringValue = ShortcutStore.currentLabel()
        recordButton.title = recording ? "Press a shortcut…  (Esc to cancel)" : "Record Custom Shortcut"
    }

    @objc private func selectPreset(_ sender: NSButton) {
        stopRecording()
        switch sender {
        case doubleShiftRadio:
            ShortcutStore.setKind(.doubleShift)
        case optionTwoRadio:
            ShortcutStore.set(.default)          // ⌥2 chord
            ShortcutStore.setKind(.chord)
        default:
            break
        }
        refresh()
    }

    @objc private func toggleRecord() {
        recording ? stopRecording() : startRecording()
        refresh()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {                       // Esc
                self.stopRecording(); self.refresh(); return nil
            }
            if let shortcut = Shortcut.from(event) {        // requires a modifier
                ShortcutStore.set(shortcut)
                ShortcutStore.setKind(.chord)               // HotkeyManager re-registers
                self.stopRecording(); self.refresh()
                Overlay.show("Shortcut set to \(shortcut.label)", symbol: "keyboard")
            }
            return nil   // consume while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    @objc private func resetDefault() {
        stopRecording()
        ShortcutStore.setKind(.doubleShift)
        refresh()
    }
}

// MARK: - Shared small helpers

// One width for every Settings pane so the window doesn't jump between tabs.
let settingsContentWidth: CGFloat = 520

extension NSViewController {
    // Pins a settings stack inside a self-sizing container, makes every card
    // span the full width (so trailing controls align), and installs it as the
    // controller's view + preferred size. Shared by the settings panes.
    func installSettingsPane(_ stack: NSStackView, cards: [NSView],
                             spacing: CGFloat = 6, fixedHeight: CGFloat? = nil) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])
        for card in cards {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        // Size the pane to its content (+ 24pt top/bottom inset) so adding rows
        // never clips the bottom, unless a caller pins a fixed height (for a pane
        // whose visible controls change at runtime).
        stack.layoutSubtreeIfNeeded()
        let height = fixedHeight ?? (stack.fittingSize.height + 48)
        container.frame = NSRect(x: 0, y: 0, width: settingsContentWidth, height: height)
        view = container
        preferredContentSize = NSSize(width: settingsContentWidth, height: height)
    }
}

func sectionHeader(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title.uppercased())
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
}

// A small secondary caption (footnotes, version line).
func settingsFootnote(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    // Pin the wrap width to the pane's content width (minus the 24pt insets), so
    // the label reports an ACCURATE wrapped height. Without this a wrapping label's
    // fittingSize is measured at an undefined width, which made the pane over-tall
    // (a long empty "chin" below the content).
    label.preferredMaxLayoutWidth = settingsContentWidth - 48
    return label
}

// One row inside a card: a leading label and a trailing control, aligned so the
// control column lines up across rows regardless of label width.
func settingsRow(_ label: String, _ control: NSView) -> NSView {
    let text = NSTextField(labelWithString: label)
    text.setContentHuggingPriority(.defaultLow, for: .horizontal)
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    control.setContentHuggingPriority(.required, for: .horizontal)

    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
    row.addView(text, in: .leading)
    row.addView(control, in: .trailing)
    row.translatesAutoresizingMaskIntoConstraints = false
    row.heightAnchor.constraint(equalToConstant: 34).isActive = true
    return row
}

// Groups related rows into a rounded, inset "card" with hairline separators
// between rows — the native macOS System Settings grouping.
func settingsCard(_ rows: [NSView]) -> NSView {
    let content = NSStackView()
    content.orientation = .vertical
    content.spacing = 0
    content.alignment = .leading
    content.translatesAutoresizingMaskIntoConstraints = false

    for (index, row) in rows.enumerated() {
        if index > 0 {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            content.addArrangedSubview(separator)
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        }
        content.addArrangedSubview(row)
        row.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
    }

    let box = NSBox()
    box.boxType = .custom
    box.titlePosition = .noTitle
    box.cornerRadius = 10
    box.fillColor = .controlBackgroundColor
    box.borderColor = .separatorColor
    box.borderWidth = 1
    box.contentViewMargins = .zero
    box.translatesAutoresizingMaskIntoConstraints = false
    if let cv = box.contentView {
        cv.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cv.topAnchor),
            content.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        ])
    }
    return box
}

func spacer(_ height: CGFloat) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: height).isActive = true
    return view
}
