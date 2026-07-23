import AppKit
import Carbon
import OSLog

// Registers the configurable conversion hotkey (default Option+2) via Carbon
// RegisterEventHotKey — the system delivers ONLY our combo, so normal typing
// never passes through us (no per-keystroke latency, unlike an event tap).
// On trigger it runs: copy selection → convert layout → paste → restore clipboard.
final class HotkeyManager {

    // Called after a conversion with the input source ID to switch to.
    var onConversion: ((String) -> Void)?

    // Fired on a double-tap of Option (⌥⌥): revert the last auto-switch fix. Kept
    // separate from convert so ⇧⇧ does exactly one thing.
    var onUndoTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var shortcutToken: NSObjectProtocol?
    private let doubleTap = DoubleTapDetector()
    // Revert gesture. Independent of the convert shortcut (double-shift or chord),
    // so it runs in both modes. A chord press includes a non-modifier key, which
    // makes it a "dirty" tap, so an Option-bearing chord can never trip this.
    private let undoDoubleTap = DoubleTapDetector(modifier: .option)
    private let typingBuffer = TypingBuffer()

    // Guards against overlapping conversions when the hotkey is pressed rapidly.
    private var isConverting = false

    // Timing for the conversion hot path. View live:
    //   log stream --predicate 'subsystem == "com.talalfi.FlicKey"'
    private var conversionStart: CFAbsoluteTime = 0
    private static let perf = Logger(subsystem: "com.talalfi.FlicKey", category: "conversion")
    private static func logTiming(_ path: String, since start: CFAbsoluteTime) {
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        perf.notice("converted via \(path, privacy: .public): \(ms, format: .fixed(precision: 1), privacy: .public) ms")
    }

    // MARK: - Lifecycle

    func start() {
        installEventHandler()
        typingBuffer.start()
        doubleTap.onTrigger = { [weak self] in
            DispatchQueue.main.async { self?.smartConvert() }
        }
        undoDoubleTap.onTrigger = { [weak self] in
            DispatchQueue.main.async { self?.onUndoTrigger?() }
        }
        // The first click after audio idle is slow (hardware spin-up); a tap of
        // either gesture's modifier is the earliest hint a click is imminent.
        doubleTap.onWatchedDown = { SoundEffect.warm() }
        undoDoubleTap.onWatchedDown = { SoundEffect.warm() }
        undoDoubleTap.start()   // active in both convert modes
        apply()
        shortcutToken = NotificationCenter.default.addObserver(
            forName: .conversionShortcutChanged, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        }
    }

    // Balances start(): removes the Carbon handler and hotkey (both installed with
    // an unretained self pointer), drops the shortcut observer, and stops the
    // double-tap and typing-buffer monitors. Backstopped by deinit.
    func stop() {
        if let shortcutToken {
            NotificationCenter.default.removeObserver(shortcutToken)
            self.shortcutToken = nil
        }
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        doubleTap.stop()
        undoDoubleTap.stop()
        typingBuffer.stop()
    }

    deinit { stop() }

    // Activate exactly one trigger mode for the current setting.
    private func apply() {
        switch ShortcutStore.currentKind() {
        case .doubleShift:
            unregisterHotKey()
            doubleTap.start()
        case .chord:
            doubleTap.stop()
            registerHotKey()
        }
    }

    // MARK: - Carbon hot key

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.smartConvert() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func registerHotKey() {
        unregisterHotKey()
        let shortcut = ShortcutStore.current()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B464C50), id: 1) // 'KFLP'
        RegisterEventHotKey(UInt32(shortcut.keyCode),
                            carbonModifiers(from: shortcut.cgFlags),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        if flags.contains(.maskControl) { mods |= UInt32(controlKey) }
        if flags.contains(.maskShift) { mods |= UInt32(shiftKey) }
        return mods
    }

    // MARK: - Smart convert flow

    // The user is still physically holding the modifier(s) when the hotkey fires.
    // Synthetic Cmd+C/Cmd+A/Cmd+V get those live modifiers merged in, corrupting
    // them (Option+Cmd+C ≠ copy). Wait until the keys are released before posting
    // anything. Caps at ~300ms so we never hang.
    private func whenModifiersClear(attempt: Int = 0, _ action: @escaping () -> Void) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let stillHeld = flags.contains(.maskAlternate)
            || flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskShift)
        if !stillHeld || attempt >= 30 {
            action()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.whenModifiersClear(attempt: attempt + 1, action)
            }
        }
    }

    private func smartConvert() {
        if isConverting { return }
        isConverting = true
        conversionStart = CFAbsoluteTimeGetCurrent()

        // FASTEST PATH — we already captured what was just typed. Replace it in
        // place with synthetic backspaces + retype. No clipboard, no AX, no
        // selection needed. This is the path for "type gibberish → double-Shift".
        // Search fields (Spotlight, browser toolbar search) hide an auto-complete
        // suggestion that AX can't see and that eats the first Backspace, so the
        // router replaces the WHOLE field via select-all + type; plain fields get
        // the in-place delete + retype. The decision is a pure, unit-tested
        // function (ConversionRouter.replacePlan) — only the execution lives here.
        let typed = typingBuffer.text
        let searchValue = typed.isEmpty ? nil : AXTextEditor.focusedSearchFieldValue()
        if let plan = ConversionRouter.replacePlan(typed: typed, searchFieldValue: searchValue) {
            typingBuffer.suspendDuringEdit()
            switch plan {
            case let .searchReplace(converted, targetSourceID):
                Self.perf.notice("search replace -> \(converted.count, privacy: .public)")
                whenModifiersClear { [weak self] in
                    guard let self else { return }
                    ClipboardManager.postKey(keyCode: 0, flags: .maskCommand)   // select all
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        KeyInput.typeText(converted, paced: true)   // search fields drop zero-gap bursts
                        if let targetSourceID { self.onConversion?(targetSourceID) }
                        SoundEffect.playClick(); SwitchStats.record(.manualConvert)
                        self.typingBuffer.finishEdit(adopting: converted)
                        Self.logTiming("search", since: self.conversionStart)
                        self.finishConversion()
                    }
                }
            case let .backspaceReplace(count, converted, targetSourceID):
                whenModifiersClear { [weak self] in
                    guard let self else { return }
                    KeyInput.deleteBackward(count)
                    KeyInput.typeText(converted)
                    if let targetSourceID { self.onConversion?(targetSourceID) }
                    SoundEffect.playClick(); SwitchStats.record(.manualConvert)
                    self.typingBuffer.finishEdit(adopting: converted)
                    Self.logTiming("buffer", since: self.conversionStart)
                    self.finishConversion()
                }
            }
            return
        }

        // FALLBACK A — Accessibility read + replace of an existing selection.
        if let (element, selected) = AXTextEditor.selection() {
            let (converted, targetSourceID) = ConversionRouter.convertText(selected)
            if AXTextEditor.replaceSelection(element, with: converted) {
                if let targetSourceID { onConversion?(targetSourceID) }
                SoundEffect.playClick(); SwitchStats.record(.manualConvert)
                Self.logTiming("AX", since: conversionStart)
                finishConversion()
                return
            }
        }

        // SLOW PATH — clipboard fallback. Must wait for held modifiers to clear
        // before posting synthetic ⌘C/⌘V.
        whenModifiersClear { [weak self] in self?.runConvertFlow() }
    }

    // Called on every terminal path to release the re-entrancy guard.
    private func finishConversion() {
        isConverting = false
    }

    private func runConvertFlow() {
        let snapshot = ClipboardManager.save()

        ClipboardManager.copySelection { [weak self] selected in
            guard let self = self else { return }

            if let text = selected, !text.isEmpty {
                self.convertAndPaste(text, snapshot: snapshot)
            } else {
                // Nothing selected → select all, then copy + convert.
                ClipboardManager.postKey(keyCode: 0, flags: .maskCommand) // 'a'
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    ClipboardManager.copySelection { selectedAll in
                        if let text = selectedAll, !text.isEmpty {
                            self.convertAndPaste(text, snapshot: snapshot)
                        } else {
                            Overlay.show("No text to convert", symbol: "character.cursor.ibeam")
                            ClipboardManager.restore(snapshot)
                            self.finishConversion()
                        }
                    }
                }
            }
        }
    }

    private func convertAndPaste(_ text: String, snapshot: ClipboardSnapshot) {
        let (converted, targetSourceID) = ConversionRouter.convertText(text)
        SoundEffect.playClick(); SwitchStats.record(.manualConvert)   // satisfying feedback the moment a fix lands
        ClipboardManager.paste(converted, onPasted: { [weak self] in
            // Switch layout the instant ⌘V is posted — don't wait for the
            // clipboard-restore delay — so it feels immediate.
            if let targetSourceID { self?.onConversion?(targetSourceID) }
            Self.logTiming("clipboard", since: self?.conversionStart ?? CFAbsoluteTimeGetCurrent())
        }, thenRestore: snapshot, completion: { [weak self] in
            self?.finishConversion()
        })
    }
}
