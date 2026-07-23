import AppKit

// Shows the "FlicKey has helped you N times, support us" nudge to non-licensed
// users once per 1000-switch milestone. Licensed users never see it, and the
// stats tab has a checkbox to turn it off entirely.
//
// QA finding 0.5.0-4: the trigger IS a switch, i.e. the user is mid-typing. So
// this must not activate the app, must not take keyboard focus, and must not run
// a modal loop (which would also starve conversion, see QA 0.5.0-2). It shows a
// non-activating floating panel a few seconds later; clicks work, typing is
// never interrupted.
enum StatsNagController {
    private static let lastKey = "statsNagLastMilestone"
    private static let disabledKey = "statsNagDisabled"
    private static var panel: NSPanel?

    // User opt-out, settable from the stats tab.
    static var isDisabled: Bool {
        get { AppDefaults.store.bool(forKey: disabledKey) }
        set { AppDefaults.store.set(newValue, forKey: disabledKey) }
    }

    // Called after each recorded switch (via the switchStatsChanged notification).
    static func checkAndNagIfNeeded() {
        guard !UITestMode.isActive, !isDisabled, !LicenseStore.isLicensed else { return }
        let last = AppDefaults.store.integer(forKey: lastKey)
        guard let milestone = StatsNag.milestone(total: SwitchStats.total, lastNagged: last) else { return }
        AppDefaults.store.set(milestone, forKey: lastKey)
        // Let the typing burst that crossed the milestone finish first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { show(count: milestone) }
    }

    private static func show(count: Int) {
        guard panel == nil else { return }
        let n = count.formatted()

        // .nonactivatingPanel: clicks land on the buttons without activating the
        // app or pulling keyboard focus out of whatever the user is typing in.
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
                            styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "FlicKey"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        Self.panel = panel

        let title = NSTextField(labelWithString: "FlicKey has helped you \(n) times")
        title.font = .systemFont(ofSize: 15, weight: .bold)

        let body = NSTextField(wrappingLabelWithString:
            "That is \(n) keyboard mix-ups it quietly sorted out for you. FlicKey's source "
            + "is public and free; if it has earned its keep, a one-time purchase keeps it "
            + "going. No subscription.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor

        let support = NSButton(title: "Support FlicKey", target: Trampoline.shared,
                               action: #selector(Trampoline.support))
        support.bezelStyle = .rounded
        let later = NSButton(title: "Maybe later", target: Trampoline.shared,
                             action: #selector(Trampoline.close))
        later.bezelStyle = .rounded
        let buttons = NSStackView(views: [NSView(), later, support])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 16, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                           constant: -(stack.edgeInsets.left + stack.edgeInsets.right)),
        ])
        panel.contentView = container
        panel.center()
        panel.orderFrontRegardless()   // deliberately no makeKey, no NSApp.activate
    }

    static func dismiss() {
        panel?.close()
        panel = nil
    }

    private final class Trampoline: NSObject {
        static let shared = Trampoline()
        @objc func support() {
            NSWorkspace.shared.open(LicenseStore.buyURL)
            StatsNagController.dismiss()
        }
        @objc func close() { StatsNagController.dismiss() }
    }
}
