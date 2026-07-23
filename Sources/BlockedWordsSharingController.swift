import AppKit

// Scheduling state for the blocked-words share prompt. In defaults; per user.
enum BlockedWordsSharingStore {
    private static var store: UserDefaults { AppDefaults.store }
    private static let lastKey = "blockedWordsLastPromptAt"
    private static let sentKey = "blockedWordsAlreadyOffered"

    static var lastPromptAt: TimeInterval {
        get { store.double(forKey: lastKey) }          // absent -> 0 -> first eligible launch is due
        set { store.set(newValue, forKey: lastKey) }
    }
    static var alreadyOffered: Set<String> {
        get { Set(store.stringArray(forKey: sentKey) ?? []) }
        set { store.set(Array(newValue).sorted(), forKey: sentKey) }
    }
}

// Drives the opt-out beta prompt: every so often (and only when there are new
// blocked words) offer to email us the exact list so auto-switch can learn.
// Fully gated, fully transparent, one click to send.
//
// QA BUG 0.5.0-2: this must NEVER be a modal alert on the launch path. A modal
// run loop from launch starves the main-queue conversion pipeline, so auto-fix,
// double-Shift and double-Option all go dead while the (often invisible) dialog
// waits — while per-app/per-site switching keeps working. A plain non-blocking
// panel has none of that: the app keeps converting while the offer is open.
final class BlockedWordsSharingController: NSObject, NSWindowDelegate {
    static let shared = BlockedWordsSharingController()

    private static let supportEmail = "flickey.support@gmail.com"
    private var panel: NSPanel?
    private var offeredWords: [String] = []
    private var allBlocked: [String] = []
    private var resolved = false   // a button was clicked (vs. red-close)

    static func runIfNeeded(now: TimeInterval = Date().timeIntervalSince1970) {
        guard !UITestMode.isActive, DiagnosticConsent.shareBlockedWordsEnabled else { return }
        let blocked = AutoSwitchExceptions().blockedWords()
        let decision = BlockedWordsSharing.decide(
            now: now,
            lastPromptAt: BlockedWordsSharingStore.lastPromptAt,
            blocked: blocked,
            alreadyOffered: BlockedWordsSharingStore.alreadyOffered)
        guard decision.shouldPrompt else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            shared.present(newWords: decision.newWords, allBlocked: blocked)
        }
    }

    private func present(newWords: [String], allBlocked: [String]) {
        guard panel == nil else { return }
        offeredWords = newWords
        self.allBlocked = allBlocked
        resolved = false

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 320),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "FlicKey"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false   // see QA 0.5.0-1; LSUIElement is rarely "active"
        panel.level = .floating
        panel.delegate = self
        self.panel = panel

        let title = NSTextField(labelWithString: "Help improve FlicKey auto-switch?")
        title.font = .systemFont(ofSize: 15, weight: .bold)

        let n = newWords.count
        let body = NSTextField(wrappingLabelWithString:
            "FlicKey can email us \(n) word\(n == 1 ? "" : "s") that shouldn't have been "
            + "auto-fixed, so it learns to leave \(n == 1 ? "it" : "them") alone. This is "
            + "exactly what gets sent, nothing else.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        let text = NSTextView()
        text.isEditable = false
        text.isRichText = false
        text.string = newWords.sorted().joined(separator: "\n")
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = text

        let send = NSButton(title: "Send\u{2026}", target: self, action: #selector(send(_:)))
        send.bezelStyle = .rounded
        send.keyEquivalent = "\r"
        let notNow = NSButton(title: "Not now", target: self, action: #selector(notNow(_:)))
        notNow.bezelStyle = .rounded
        let stop = NSButton(title: "Stop asking", target: self, action: #selector(stopAsking(_:)))
        stop.bezelStyle = .rounded
        let buttons = NSStackView(views: [stop, NSView(), notNow, send])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, body, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                          constant: -(stack.edgeInsets.left + stack.edgeInsets.right)),
            buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        panel.contentView = container
        panel.center()
        panel.orderFrontRegardless()
    }

    @objc private func send(_ sender: Any?) {
        let r = BlockedWordsSharing.report(words: offeredWords,
                                           installID: DiagnosticConsent.installID,
                                           appVersion: DiagnosticRecorder.bundleVersion())
        if let email = NSSharingService(named: .composeEmail), email.canPerform(withItems: [r.body]) {
            email.recipients = [Self.supportEmail]
            email.subject = r.subject
            email.perform(withItems: [r.body])
        } else {
            let picker = NSSharingServicePicker(items: [r.body])
            if let anchor = panel?.contentView {
                picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
            }
        }
        BlockedWordsSharingStore.alreadyOffered =
            BlockedWordsSharingStore.alreadyOffered.union(allBlocked)
        BlockedWordsSharingStore.lastPromptAt = Date().timeIntervalSince1970
        finish()
    }

    @objc private func notNow(_ sender: Any?) {
        BlockedWordsSharingStore.lastPromptAt = Date().timeIntervalSince1970
        finish()
    }

    @objc private func stopAsking(_ sender: Any?) {
        DiagnosticConsent.shareBlockedWordsEnabled = false
        finish()
    }

    // Red-close without a button = "Not now": quiet for another interval, so the
    // offer can't re-arm on every launch.
    func windowWillClose(_ notification: Notification) {
        if !resolved { BlockedWordsSharingStore.lastPromptAt = Date().timeIntervalSince1970 }
        panel = nil
    }

    private func finish() {
        resolved = true
        panel?.close()
        panel = nil
    }
}
