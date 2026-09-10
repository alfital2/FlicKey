import AppKit
import Carbon

// Coordinates automatic wrong-layout correction. Watches completed words via
// TypedWordTracker, and when two consecutive words are confidently wrong-layout
// (misspelled where typed, valid once swapped, and not blocked), rewrites the run
// in place and switches the input source. A manual ⇧⇧ within a short window
// undoes it and records a rejection for those words; a word is blocked from
// auto-switching only after enough rejections (see AutoSwitchExceptions), and a
// fix left standing counts as acceptance and forgives prior rejections.
// Opt-in: does nothing unless AutoSwitchSettings.isEnabled.
//
// The decisions live in WrongLayoutClassifier / AutoSwitchStreak /
// AutoSwitchExceptions (all unit-tested); this shell owns the monitor, the
// synthetic edit, secure-field gating, and the undo timing.
final class AutoSwitchController {

    // Called right before an auto-switch changes the input source, so the layout
    // cue is muted for the switch we cause (one "fix landed" click, not the click
    // plus the cue's taps). Wired to LayoutCueController.suppress.
    var suppressCue: (() -> Void)?

    private let tracker = TypedWordTracker()
    private let classifier = WrongLayoutClassifier(
        spellChecker: SystemSpellChecker(),
        candidates: { LayoutConverter.candidates($0) })
    private let exceptions = AutoSwitchExceptions()
    private var streak = AutoSwitchStreak()

    private struct PendingUndo {
        let originalRun: String
        let convertedRun: String
        let previousSourceID: String?
        let at: TimeInterval
    }
    private var pendingUndo: PendingUndo?
    private static let undoWindow: TimeInterval = 4

    // The words of the most recent auto-fix, on probation until the undo window
    // passes. Undoing records a rejection and clears this; anything else (typing
    // on, clicking away, the window expiring) counts as acceptance and forgives
    // the words' prior rejections. Only an undo clears it, so every non-undo path
    // resolves to acceptance. Tagged with the edit generation so a later fix or
    // an undo's own rewrite can't be mistaken for this fix surviving.
    private var pendingApproval: (words: [String], generation: Int)?

    // Fire only after a genuine quiet gap, on a WORD boundary. FlicKey's monitor is passive
    // — it cannot hold the user's keystrokes back — so firing while they are still typing
    // makes the synthetic rewrite collide with real keys (garbled text, seen badly in
    // Finder's type-ahead). A pending fire is scheduled only when a word completes, and the
    // very next keystroke cancels it, so it goes off ONLY when typing has actually paused;
    // under continuous typing it just defers to the natural pause — no mid-word, no
    // collision. (A confidently wrong run stays armed until that pause; b23's ambiguous
    // riding means an intended-word boundary no longer kills it.)
    private var pendingFire: DispatchWorkItem?
    private var pendingFireSignal: SlipSignal = .misspelled   // the firing word's evidence
    private static let fireQuietGap: TimeInterval = 0.15

    // Consecutive carried near-miss words (flagged as slips but with no valid swap) since
    // the last confident/ambiguous word. A confident wrong-layout run tolerates a few —
    // dict-gap Hebrew words and names typed on the wrong layout — and converts them with
    // the passage; too many in a row means it probably isn't wrong-layout after all, so the
    // run breaks. A real English word (notSlip whose swap is gibberish) breaks it at once.
    private var carriedOpaque = 0
    private static let maxCarriedOpaque = 2

    // Distinguishes overlapping synthetic edits so an earlier edit's scheduled
    // "resume" can't un-suspend the tracker in the middle of a later one.
    private var editGeneration = 0

    // Accessibility may be granted after launch. A global NSEvent monitor made
    // before then can be absent or inert, so defer installation until trust is
    // present and keep checking. The same loop notices later permission
    // revocation and rebuilds the monitor when access returns.
    private var monitorCheck: DispatchWorkItem?
    private var monitorGeneration = 0
    private var monitorRecovery = AutoSwitchMonitorRecoverySchedule()
    private var monitorUnavailableLogged = false
    private static let monitorHealthyCheckInterval: TimeInterval = 10

    // MARK: - Lifecycle

    func start() {
        guard AutoSwitchSettings.isEnabled else { return }
        // Warm AppleSpell before the first real word arrives, RETRYING across
        // launch: at boot (login-item start) the daemon can stay cold for
        // seconds, and a single early probe both misses and burns one of the
        // negative-probe retries (see SystemSpellChecker). Spaced attempts let a
        // cold daemon flip each language to a permanent positive early, while a
        // genuinely broken dictionary converges to its stable "off".
        warmDictionaries(attempt: 0)
        tracker.onWordCompleted = { [weak self] word, endedBySpace in
            self?.wordCompleted(word, endedBySpace: endedBySpace)
        }
        tracker.onRegionBreak = { [weak self] kind in
            guard let self else { return }
            // Only a break that killed a live streak is diagnostic ("typed two
            // wrong words then Enter" is the classic why-didn't-it-fire report).
            if self.streak.count > 0 { Diag.log(.autoSwitchRunBroken(by: kind)) }
            self.streak.breakRun()
            self.carriedOpaque = 0
            self.disarmFire()
            // A click, chord, or app switch moves the caret/context, so the
            // pending undo's delete-count no longer describes the focused text;
            // ⇧⇧ must fall through to a normal manual conversion, never rewrite
            // whatever now has focus.
            self.pendingUndo = nil
        }
        tracker.onInput = { [weak self] isBackspace in
            guard let self else { return }
            self.pendingUndo = nil           // typed on → undo expires
            if isBackspace {
                // The user is editing the run; the words the streak classified may
                // no longer be on screen. Disarm and let the next completed word
                // re-classify and re-arm.
                self.disarmFire()
            } else {
                // Still typing: push a pending fire out one quiet gap past THIS key, so it
                // goes off a fixed moment after typing STOPS — whether or not the last word
                // ended in a space. During a burst each key defers it again, so it never
                // fires mid-burst; it only lands once you actually pause.
                self.rescheduleFireIfPending()
            }
        }
        beginMonitorHealthChecks()
    }

    // Spaced dictionary warm-up: probe now, then again at growing intervals while
    // any enabled language still lacks a functional dictionary. Stops as soon as
    // every language answers positive, or after the last attempt (at which point
    // the negative-probe budget in SystemSpellChecker is close to final anyway).
    private static let warmupDelays: [TimeInterval] = [0.5, 1, 2, 4, 8]
    private func warmDictionaries(attempt: Int) {
        let languages = WordScript.primaryLanguages(of: InputSourceCatalog.enabledSources())
        let allFunctional = classifier.warmDictionaries(for: languages)
        guard !allFunctional, attempt < Self.warmupDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmupDelays[attempt]) { [weak self] in
            self?.warmDictionaries(attempt: attempt + 1)
        }
    }

    func stop() {
        monitorGeneration += 1
        monitorCheck?.cancel()
        monitorCheck = nil
        monitorRecovery.reset()
        monitorUnavailableLogged = false
        tracker.stop()
        AutoSwitchMonitorHealth.set(.inactive)
        streak.breakRun()
        carriedOpaque = 0
        disarmFire()
        pendingUndo = nil
        pendingApproval = nil
    }

    private func beginMonitorHealthChecks() {
        monitorGeneration += 1
        monitorCheck?.cancel()
        monitorRecovery.reset()
        monitorUnavailableLogged = false
        checkTypingMonitor(generation: monitorGeneration)
    }

    private func checkTypingMonitor(generation: Int) {
        guard generation == monitorGeneration, AutoSwitchSettings.isEnabled else { return }

        let trusted = AXIsProcessTrusted()
        let active: Bool
        if trusted {
            active = tracker.start()
        } else {
            // Discard any token created before trust was granted. Reinstalling
            // after the transition avoids a non-nil but non-delivering monitor.
            tracker.stop()
            active = false
        }

        if active {
            if monitorUnavailableLogged {
                Diag.log(.autoSwitchMonitorRecovered(attempts: monitorRecovery.attemptsIssued))
            }
            monitorUnavailableLogged = false
            monitorRecovery.reset()
            AutoSwitchMonitorHealth.set(.available)
            scheduleMonitorCheck(after: Self.monitorHealthyCheckInterval, generation: generation)
            return
        }

        let issue: AutoSwitchMonitorIssue = trusted ? .monitorCreationFailed : .accessibilityDenied
        if !monitorUnavailableLogged {
            Diag.log(.autoSwitchMonitorUnavailable(reason: issue))
            monitorUnavailableLogged = true
        }
        AutoSwitchMonitorHealth.set(.unavailable(issue))
        scheduleMonitorCheck(after: monitorRecovery.takeNextDelay(), generation: generation)
    }

    private func scheduleMonitorCheck(after delay: TimeInterval, generation: Int) {
        monitorCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.checkTypingMonitor(generation: generation)
        }
        monitorCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // Called after the undo window: if this fix's words are still on probation
    // (never undone), the user accepted the conversion, so forgive prior rejections.
    private func resolveApproval(generation: Int) {
        guard let approval = pendingApproval, approval.generation == generation else { return }
        approval.words.forEach { exceptions.recordAcceptance($0) }
        pendingApproval = nil
    }

    // MARK: - Detection

    private func wordCompleted(_ word: String, endedBySpace: Bool) {
        // A keystroke already cancelled any pending fire; a completing word re-arms it
        // below if the run is (still) confidently wrong-layout, or ends the run.
        pendingFire?.cancel(); pendingFire = nil
        // Only a soft space can continue a run; a hard break already reset the streak via
        // onRegionBreak, so just drop the run and wait for fresh typing.
        guard endedBySpace else { endRun(); return }

        let script = WordScript.script(for: word).rawValue
        let length = word.count

        guard !exceptions.isBlocked(word) else {
            // Blocked words look like "detection stopped working" in the field;
            // the trail says the user taught it that.
            Diag.log(.autoSwitchRejected(reason: .learnedException, script: script, wordLength: length))
            endRun()
            return
        }

        switch classifier.verdict(word) {
        case .match(let match):
            carriedOpaque = 0
            let countBefore = streak.count
            let armed = streak.word(.wrongLayout(targetSourceID: match.targetSourceID,
                                                 isSingleLetter: length == 1))
            if armed {
                pendingFireSignal = match.signal
                armFire()
            } else if countBefore > 0 && streak.count == 1 {
                // Target disagreement restarted the streak at this word: the run must
                // restart with it too, or a later fire would rewrite the earlier words
                // toward a layout they never matched.
                Diag.log(.autoSwitchRejected(reason: .targetDisagreed, script: script, wordLength: length))
                disarmFire()
                tracker.resetRun(keeping: word + " ")
            } else if countBefore == 0 {
                Diag.log(.autoSwitchStreakOpened(signal: match.signal, script: script, wordLength: length))
            }

        case .notSlip:
            // A word valid as typed can still be an ambiguous member of a wrong-layout
            // passage (a real function word like את/כן/في that also spells a valid English
            // token). It rides the run and can keep it alive, but never arms on its own.
            if let target = ambiguousTarget(for: word) {
                carriedOpaque = 0
                let armed = streak.word(.ambiguousLayout(targetSourceID: target))
                if armed { pendingFireSignal = .misspelled; armFire() }
                return   // ride: converts with the passage
            }
            // A valid English word whose swap is gibberish is intentional English. It is
            // the boundary that protects real English from a nearby wrong-layout run.
            if streak.count > 0 {
                Diag.log(.autoSwitchRejected(reason: .endedStreak, script: script, wordLength: length))
            }
            endRun()

        case .slipWithoutValidSwap:
            // A near-miss: flagged as a slip but no reading validated — a dict-gap word or
            // a name typed on the wrong layout. CARRY it in the run so a confident run
            // converts it too; it lends no confidence, and a stretch of them in a row
            // (probably not wrong-layout after all) ends the run.
            Diag.log(.autoSwitchRejected(reason: .noValidSwap, script: script, wordLength: length))
            carriedOpaque += 1
            if carriedOpaque >= Self.maxCarriedOpaque {
                endRun()
            } else if streak.isArmed {
                // Keep the run going (do NOT resetRun) and fire (or arm) so the carried
                // word converts with the rest.
                armFire()
            }

        case .ineligible:
            endRun()
        }
    }

    // Ends the current run: clears the carry counter, breaks the streak, drops the
    // reconstruction run, and disarms any pending fire.
    private func endRun() {
        carriedOpaque = 0
        _ = streak.word(.ordinary)
        tracker.resetRun()
        disarmFire()
    }

    // A word the classifier judged notSlip (valid as typed) can still be ambiguous:
    // many high-frequency function words transliterate to a valid word in BOTH scripts
    // (Hebrew את→"t,", כן→"fi"; Arabic في→"td"; Russian же→";t"). Left as a boundary,
    // such a word breaks an armed streak mid-sentence or fails to join one — dropping or
    // fragmenting the whole wrong-layout passage. Returns the target layout toward which
    // the word ALSO reads as a real word: the live streak's target if it validates there,
    // else any enabled target (a leading ambiguous word that opens a provisional streak).
    // Validation uses the same functional-dictionary check that approves a match, so this
    // never triggers for languages macOS cannot spell-check (e.g. Ukrainian, Greek).
    private func ambiguousTarget(for word: String) -> String? {
        let readings = LayoutConverter.candidates(word)
        if streak.count > 0 {
            guard let target = streak.targetSourceID,
                  let reading = readings.first(where: { $0.targetSourceID == target }),
                  classifier.validatesAsRealWord(reading.converted) else { return nil }
            return target
        }
        for reading in readings where classifier.validatesAsRealWord(reading.converted) {
            return reading.targetSourceID
        }
        return nil
    }

    // MARK: - Fire scheduling

    // Schedule the fire one quiet gap out. Called only from a completed word; the next
    // keystroke cancels it (see onInput), so it fires only if typing has genuinely paused.
    private func armFire() {
        SoundEffect.warm()   // the fire clicks ≥150ms from now; wake the audio path
        pendingFire?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire() }
        pendingFire = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fireQuietGap, execute: work)
    }

    private func rescheduleFireIfPending() { if pendingFire != nil { armFire() } }
    private func disarmFire() { pendingFire?.cancel(); pendingFire = nil }

    private func fire() {
        pendingFire = nil
        carriedOpaque = 0
        // Never mutate a secure/password field (secure input is on while one is focused).
        guard !IsSecureEventInputEnabled() else { streak.breakRun(); tracker.resetRun(); return }
        // A mouse button held right now means a click is in flight whose monitor
        // callback may not have cancelled us yet; the caret is moving, so abort.
        guard NSEvent.pressedMouseButtons == 0 else { streak.breakRun(); tracker.resetRun(); return }
        // Type-select surfaces (Finder file lists, etc.) aren't editable text — a rewrite
        // there has nothing to edit and just garbles the type-ahead. Never fire into them.
        guard !AXTextEditor.focusedElementIsNonEditableContainer() else {
            streak.breakRun(); tracker.resetRun(); return
        }

        // Convert toward the layout BOTH streak words validated against; with
        // three or more layouts that is not always the converter's next-in-cycle.
        // The dictionary-preferring variant picks among ambiguous readings (the
        // ArabicPC لا digraph) the same way the classifier validated the words.
        let run = tracker.currentRun
        guard let target = streak.targetSourceID,
              let result = LayoutConverter.convert(run, toSourceID: target,
                                                   preferring: { [classifier] in classifier.validatesAsRealWord($0) }),
              !result.converted.isEmpty
        else { streak.breakRun(); tracker.resetRun(); return }

        let previous = InputSourceManager.currentSourceID()
        // Delete the ACTUAL on-screen span of the run, not the tracked keystroke count:
        // text services can mutate the typed keys on screen. Falls back to the tracked count
        // (logged to the trail) only when AX can't read the field.
        let span = onScreenDeleteCount(for: run)
        // Try an ATOMIC AX replace first — ONE instant operation, no keystroke stream, so it
        // can't collide with live typing. This is the only collision-free rewrite: a synthetic
        // backspace+type burst runs for up to a SECOND in a live-search field (Spotlight),
        // long enough for the user's own keystrokes to interleave and corrupt the result
        // (`anשמע הוvא…`). Works wherever the field exposes settable text — native fields,
        // Spotlight, browser search/address bars; Electron/web/terminals no-op and fall
        // through to the synthetic path. Fires here on the quiet-gap pause, never mid-typing.
        if AXTextEditor.replaceRunBeforeCaret(count: span.count, with: result.converted) {
            editGeneration += 1
            if let switchTo = result.targetSourceID {
                suppressCue?()
                InputSourceManager.switchTo(sourceID: switchTo)
            }
            SoundEffect.playClick()
            finishFire(run: run, target: target, converted: result.converted, previous: previous)
            return
        }
        // The atomic replace didn't take. If this is a LIVE-SEARCH field that can't take it
        // (e.g. Spotlight in a run where it doesn't expose settable AX text), do NOT fall back
        // to the synthetic burst: such an overlay can dismiss MID-burst, and the leftover
        // synthetic keystrokes then land in — and rewrite converted text INTO — whatever app is
        // behind it (a data leak, BUG-A). The atomic path is the only safe rewrite for an
        // overlay search field, so abort here instead of risking the leak.
        guard !AXTextEditor.focusedElementIsSearchField() else {
            streak.breakRun(); tracker.resetRun(); return
        }
        // Synthetic fallback (Electron / web / terminal — not an overlay that dismisses
        // mid-rewrite): backspaces + typing.
        rewrite(deleteCount: span.count, type: result.converted,
                switchTo: result.targetSourceID, paced: false,
                expectedResidue: span.before.map { String($0.dropLast(span.count)) + result.converted })
        finishFire(run: run, target: target, converted: result.converted, previous: previous)
    }

    // Post-rewrite bookkeeping shared by both rewrite paths in fire() (atomic + synthetic):
    // record the undo, resolve/renew the acceptance probation, and start a fresh run.
    private func finishFire(run: String, target: String, converted: String, previous: String?) {
        Diag.log(.autoSwitchFired(target: target, signal: pendingFireSignal))
        SwitchStats.record(.autoFix)
        pendingUndo = PendingUndo(originalRun: run, convertedRun: converted,
                                  previousSourceID: previous, at: now())
        // A second fire inside the previous fix's window is a non-undo resolution of that
        // probation: the first fix survived, which is acceptance.
        if let previousApproval = pendingApproval {
            previousApproval.words.forEach { exceptions.recordAcceptance($0) }
        }
        // Put the fixed words on probation: if this fix is not undone within the window, the
        // user accepted it (resolveApproval). Tag it with the current edit generation.
        let words = run.split(separator: " ").map(String.init)
        let generation = editGeneration
        pendingApproval = (words: words, generation: generation)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow) { [weak self] in
            self?.resolveApproval(generation: generation)
        }
        carriedOpaque = 0
        tracker.resetRun()
        streak.breakRun()   // switched to the right layout now; start a fresh streak
        disarmFire()
    }

    // MARK: - Undo (driven by ⇧⇧ via HotkeyManager)

    // The ⌥⌥ revert. Returns true if it consumed a just-happened auto-switch fix
    // (revert the text + layout, count a rejection per word so repeated reverts
    // train the blocklist); false means there was nothing fresh to undo, so ⌥⌥ is
    // a no-op. Valid only within the window and before any typing (which clears
    // pendingUndo through onInput).
    func handleUndoTrigger() -> Bool {
        guard let undo = pendingUndo, now() - undo.at < Self.undoWindow else { return false }
        pendingUndo = nil
        pendingApproval = nil   // undoing is a rejection, not acceptance
        // Focus reached a secure field without a caret-moving event (rare, but
        // possible via app-driven focus): never type into it.
        guard !IsSecureEventInputEnabled() else { return false }
        let span = onScreenDeleteCount(for: undo.convertedRun)
        // Mirror fire(): prefer the ATOMIC AX replace (one exact operation, immune to
        // synthetic-keystroke loss that can drop a backspace and orphan a leading
        // char, e.g. "how are you" reverting to "h" + original). Fall back to the
        // synthetic delete+retype only where the field isn't settable (Electron /
        // web / terminal), exactly as fire() does.
        if AXTextEditor.replaceRunBeforeCaret(count: span.count, with: undo.originalRun) {
            editGeneration += 1
            if let switchTo = undo.previousSourceID {
                suppressCue?()
                InputSourceManager.switchTo(sourceID: switchTo)
            }
            SoundEffect.playClick()
        } else {
            rewrite(deleteCount: span.count, type: undo.originalRun,
                    switchTo: undo.previousSourceID,
                    paced: AXTextEditor.focusedElementIsSearchField(),
                    expectedResidue: span.before.map { String($0.dropLast(span.count)) + undo.originalRun })
        }
        // Count ONE rejection per DISTINCT word (a run like "akuo akuo" repeats
        // the word; counting each occurrence would block it from a single undo).
        // A word is only BLOCKED after enough rejections (default 2), so one
        // accidental undo never permanently blocks.
        let words = Set(undo.originalRun.split(separator: " ").map(String.init))
        words.forEach { exceptions.recordRejection($0) }
        Diag.log(.autoSwitchUndone(wordsRejected: words.count))
        return true
    }

    // How many characters to backspace to remove `run` from the focused field,
    // plus the pre-rewrite field content (for the post-rewrite self-check).
    // Prefers the ACTUAL on-screen span, which is robust to text services that
    // expand OR shrink the run: a measured span SMALLER than the tracked length
    // is trusted too (autocorrect shrank a word — deleting the measured span is
    // exactly right, and deleting less than tracked can never eat prior text; QA
    // F3 showed the old ≥-tracked guard falling back and over-deleting). Only an
    // implausibly LARGE span, or an unreadable field, falls back to the tracked
    // count — both logged to the shipping trail, since the fallback path is the
    // one place a text-service mutation is not compensated (QA F5).
    private func onScreenDeleteCount(for run: String) -> (count: Int, before: [Character]?) {
        let tracked = run.count
        guard let before = AXTextEditor.focusedTextBeforeCaret() else {
            Diag.log(.autoSwitchSpanFallback(reason: .axUnreadable))
            return (tracked, nil)
        }
        let words = run.split(separator: " ").count
        let onScreen = OnScreenSpan.length(beforeCaret: before, words: words)
        // Anti-runaway cap: a stale/misplaced read can't wipe unrelated text.
        guard onScreen <= tracked * 3 + 24 else {
            Diag.log(.autoSwitchSpanFallback(reason: .spanOutOfRange))
            return (min(tracked, before.count), before)
        }
        return (onScreen, before)
    }

    // MARK: - Synthetic edit

    // `expectedResidue` is the exact field content the rewrite should leave before
    // the caret (pre-rewrite content minus the deleted span, plus `text`), when the
    // pre-rewrite state was readable; nil falls back to the weaker tail heuristic.
    private func rewrite(deleteCount: Int, type text: String, switchTo sourceID: String?,
                         paced: Bool, expectedResidue: String? = nil) {
        tracker.beginSyntheticEdit()
        editGeneration += 1
        let generation = editGeneration

        KeyInput.deleteBackward(deleteCount, paced: paced)
        KeyInput.typeText(text, paced: paced)
        if let sourceID {
            suppressCue?()                       // mute the cue for the switch we cause
            InputSourceManager.switchTo(sourceID: sourceID)
        }
        SoundEffect.playClick()                  // same feedback as a manual ⇧⇧ fix

        // Let the synthetic events drain before watching again; only the latest
        // edit resumes, so overlapping fire+undo can't un-suspend mid-edit. The
        // drain scales with the edit size: a long run posts hundreds of events,
        // whose delivery can outlast a fixed 100ms.
        let drain = 0.1 + Double(deleteCount + text.count) * 0.001
        DispatchQueue.main.asyncAfter(deadline: .now() + drain) { [weak self] in
            guard let self, self.editGeneration == generation else { return }
            self.tracker.endSyntheticEdit()
            // Self-check: the field must now hold exactly what the rewrite PLANNED
            // (pre-rewrite content minus the deleted span, plus the typed text).
            // Catches every execution divergence: a text service re-mutating the
            // result (the undo re-autocorrect), a paced field dropping synthetic
            // events, an over- or under-delete relative to the plan. A flaw in the
            // plan itself (a mis-measured span, e.g. a multi-word text-replacement
            // expansion) is NOT detectable here — see the spec's known limitations.
            // Without a pre-rewrite snapshot it degrades to the tail heuristic.
            // Diagnostic only — never drives an edit.
            guard let after = AXTextEditor.focusedTextBeforeCaret() else { return }
            let anomaly: RewriteAnomalyKind?
            if let expectedResidue {
                anomaly = RewriteCheck.residueAnomaly(actual: after,
                                                      expected: Array(expectedResidue),
                                                      typed: Array(text))
            } else {
                anomaly = RewriteCheck.anomaly(beforeCaret: after, expected: Array(text))
            }
            if let anomaly { Diag.log(.autoSwitchRewriteAnomaly(kind: anomaly)) }
        }
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
