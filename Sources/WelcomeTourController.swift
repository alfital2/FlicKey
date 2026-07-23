import AppKit

// The animated welcome tour. Five short self-driving scenes loop:
//
//   1. wrong-layout typing fixes itself (typed live, confetti on the flip)
//   2. it speaks several languages, both directions
//   3. double-tap Shift converts on demand
//   4. double-tap Option undoes a fix
//   5. a mini browser + chat window: the layout follows tabs and conversations
//
// Everything is native animation (no bundled video): crisp, tiny, dark/light
// aware, editable copy. Panel rules follow the 0.5.0 QA lessons: floating,
// hidesOnDeactivate = false, never modal, seen only on dismiss.
//
// Every garbled string below is the TRUE key sequence of its phrase on the
// wrong layout (Hebrew standard / Russian ЙЦУКЕН / Arabic PC):
//   vhh nv bang -> היי מה נשמע      ghbdtn -> привет     rfr ltkf -> как дела
//   akuo -> שלום                     اثممخ -> hello (typed on the Arabic layout)
final class WelcomeTourController: NSObject, NSWindowDelegate {

    static let shared = WelcomeTourController()

    // Launch gate: fresh installs only. Returns true when the tour is due so the
    // caller can suppress the What's New note (a new user's first version IS the
    // baseline).
    @discardableResult
    static func showIfNeeded() -> Bool {
        guard !UITestMode.isActive else { return false }
        let firstRun = TimeInterval(TrialManager.load().firstRun)
        guard WelcomeTour.shouldShow(firstRun: firstRun,
                                     now: Date().timeIntervalSince1970,
                                     seen: WelcomeTourStore.seen) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shared.present() }
        return true
    }

    // MARK: - Panel

    private var panel: NSPanel?
    private var generation = 0            // invalidates in-flight animation steps
    private var sceneIndex = 0
    private var playedClickThisLoop = false

    private let stage = NSView()
    private let caption = NSTextField(wrappingLabelWithString: "")
    private var dots: [NSView] = []

    func present() {
        if panel != nil {
            panel?.orderFrontRegardless()
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 470),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "FlicKey"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.delegate = self
        self.panel = panel

        let title = NSTextField(labelWithString: "Welcome to FlicKey")
        title.font = roundedFont(size: 25, weight: .bold)

        let subtitle = NSTextField(labelWithString: "Watch what it does for you.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        stage.wantsLayer = true
        stage.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        stage.layer?.cornerRadius = 14
        stage.layer?.borderWidth = 1
        stage.layer?.borderColor = NSColor.separatorColor.cgColor
        stage.translatesAutoresizingMaskIntoConstraints = false
        stage.heightAnchor.constraint(equalToConstant: 210).isActive = true

        caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.alignment = .center

        let dotsRow = NSStackView()
        dotsRow.orientation = .horizontal
        dotsRow.spacing = 7
        dots = (0..<Self.scenes.count).map { _ in
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            dotsRow.addArrangedSubview(dot)
            return dot
        }
        let dotsCentered = NSStackView(views: [NSView(), dotsRow, NSView()])
        dotsCentered.orientation = .horizontal
        dotsCentered.distribution = .equalCentering

        let skip = NSButton(title: "Skip", target: self, action: #selector(dismissTour))
        skip.bezelStyle = .rounded
        let start = NSButton(title: "Get started", target: self, action: #selector(dismissTour))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        let buttons = NSStackView(views: [skip, NSView(), start])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, subtitle, stage, caption, dotsCentered, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 20, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.addSubview(stack)
        let inset = stack.edgeInsets.left + stack.edgeInsets.right
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stage.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -inset),
            caption.widthAnchor.constraint(equalTo: stage.widthAnchor),
            dotsCentered.widthAnchor.constraint(equalTo: stage.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stage.widthAnchor),
        ])
        panel.contentView = container
        panel.center()
        panel.orderFrontRegardless()

        sceneIndex = 0
        playedClickThisLoop = false
        runCurrentScene()
    }

    @objc private func dismissTour() {
        WelcomeTourStore.seen = true
        generation += 1
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        WelcomeTourStore.seen = true      // red-close counts as seen too
        generation += 1
        panel = nil
    }

    // MARK: - Scene engine

    private typealias Scene = (title: String, run: (WelcomeTourController, @escaping () -> Void) -> Void)

    private static let scenes: [Scene] = [
        ("Type in the wrong layout. FlicKey fixes it and switches, by itself.",
         { c, done in c.sceneAutoFix(done) }),
        ("Hebrew, Russian, Arabic and more. Both directions.",
         { c, done in c.sceneLanguages(done) }),
        ("Convert anything on demand: double-tap Shift.",
         { c, done in c.sceneDoubleShift(done) }),
        ("Feel it and hear it: a gentle trackpad tap and a click when a fix lands.",
         { c, done in c.sceneFeedback(done) }),
        ("It remembers your language per tab, per chat, per app.",
         { c, done in c.sceneMemory(done) }),
    ]

    private func runCurrentScene() {
        guard panel != nil else { return }
        generation += 1
        let gen = generation
        stage.subviews.forEach { $0.removeFromSuperview() }
        caption.stringValue = Self.scenes[sceneIndex].title
        for (i, dot) in dots.enumerated() {
            dot.layer?.backgroundColor = (i == sceneIndex ? NSColor.controlAccentColor
                                                          : NSColor.quaternaryLabelColor).cgColor
        }
        Self.scenes[sceneIndex].run(self) { [weak self] in
            self?.after(1.5, gen: gen) {
                guard let self else { return }
                self.sceneIndex = (self.sceneIndex + 1) % Self.scenes.count
                if self.sceneIndex == 0 { self.playedClickThisLoop = false }
                self.runCurrentScene()
            }
        }
    }

    private func after(_ delay: TimeInterval, gen: Int? = nil, _ block: @escaping () -> Void) {
        let expected = gen ?? generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == expected else { return }
            block()
        }
    }

    // MARK: - Stage furniture

    private func makeMockField(width: CGFloat = 380) -> (text: NSTextField, field: NSView, pill: NSTextField) {
        let field = NSView()
        field.wantsLayer = true
        field.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        field.layer?.cornerRadius = 10
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        field.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: "")
        text.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        text.wantsLayer = true
        text.translatesAutoresizingMaskIntoConstraints = false

        let caret = NSView()
        caret.wantsLayer = true
        caret.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        caret.translatesAutoresizingMaskIntoConstraints = false
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1; blink.toValue = 0
        blink.duration = 0.5; blink.autoreverses = true; blink.repeatCount = .infinity
        caret.layer?.add(blink, forKey: "blink")

        let pill = makePill("ABC", active: false)

        field.addSubview(text)
        field.addSubview(caret)
        stage.addSubview(field)
        stage.addSubview(pill)
        NSLayoutConstraint.activate([
            field.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: stage.centerYAnchor, constant: -18),
            field.widthAnchor.constraint(equalToConstant: width),
            field.heightAnchor.constraint(equalToConstant: 50),
            text.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            caret.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 1),
            caret.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            caret.widthAnchor.constraint(equalToConstant: 2),
            caret.heightAnchor.constraint(equalToConstant: 24),
            pill.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14),
            pill.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
        ])
        return (text, field, pill)
    }

    private func makePill(_ label: String, active: Bool) -> NSTextField {
        let pill = NSTextField(labelWithString: label)
        pill.font = .systemFont(ofSize: 12, weight: .bold)
        pill.alignment = .center
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.35)
                                              : NSColor.quaternaryLabelColor).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        pill.heightAnchor.constraint(equalToConstant: 19).isActive = true
        return pill
    }

    private func setPill(_ pill: NSTextField, to label: String, active: Bool) {
        pill.stringValue = label
        pill.layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.35)
                                              : NSColor.quaternaryLabelColor).cgColor
        springPop(pill)
    }

    private func springPop(_ view: NSView) {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.75
        spring.toValue = 1.0
        spring.damping = 9
        spring.initialVelocity = 6
        spring.duration = spring.settlingDuration
        view.layer?.add(spring, forKey: "pop")
    }

    private func typeText(_ string: String, into label: NSTextField,
                          then: @escaping () -> Void) {
        var index = 0
        let chars = Array(string)
        func typeNext() {
            guard index < chars.count else { then(); return }
            label.stringValue.append(chars[index])
            index += 1
            after(TimeInterval.random(in: 0.055...0.095)) { typeNext() }
        }
        typeNext()
    }

    // The conversion moment: quick fade of the garble, fast ripple-reveal of the
    // converted text, spring pop, green-flash border, confetti puff, click.
    private func convert(_ label: NSTextField, in field: NSView?, to converted: String,
                         pill: NSTextField, pillText: String, then: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            label.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            label.stringValue = ""
            label.alphaValue = 1
            let chars = Array(converted)
            var i = 0
            func reveal() {
                guard i < chars.count else {
                    self.springPop(label)
                    self.setPill(pill, to: pillText, active: true)
                    if let field {
                        self.flashBorder(field)
                        self.confetti(near: field)
                    }
                    if !self.playedClickThisLoop {
                        self.playedClickThisLoop = true
                        SoundEffect.preview(SoundEffect.selected)
                    }
                    self.after(0.25) { then() }
                    return
                }
                label.stringValue.append(chars[i])
                i += 1
                self.after(0.02) { reveal() }
            }
            reveal()
        })
    }

    private func flashBorder(_ field: NSView) {
        let flash = CABasicAnimation(keyPath: "borderColor")
        flash.fromValue = NSColor.systemGreen.cgColor
        flash.toValue = NSColor.tertiaryLabelColor.cgColor
        flash.duration = 0.8
        field.layer?.add(flash, forKey: "flash")
    }

    // A small one-shot confetti puff at the field's trailing edge.
    private func confetti(near view: NSView) {
        guard let spark = sparkImage() else { return }
        let emitter = CAEmitterLayer()
        emitter.frame = stage.bounds
        let f = view.frame
        emitter.emitterPosition = CGPoint(x: f.maxX - 12, y: f.midY)
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        emitter.emitterCells = [NSColor.systemPink, .systemYellow, .systemTeal, .white].map { color in
            let cell = CAEmitterCell()
            cell.contents = spark
            cell.color = color.cgColor
            cell.birthRate = 220
            cell.lifetime = 0.8
            cell.velocity = 90
            cell.velocityRange = 40
            cell.emissionRange = .pi * 2
            cell.yAcceleration = -180
            cell.scale = 0.3
            cell.scaleSpeed = -0.35
            cell.alphaSpeed = -1.2
            cell.spin = 3
            return cell
        }
        stage.layer?.addSublayer(emitter)
        after(0.1) { emitter.birthRate = 0 }
        after(1.1) { emitter.removeFromSuperlayer() }
    }

    private func sparkImage(diameter: CGFloat = 7) -> CGImage? {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func makeKeycap(_ symbol: String) -> NSView {
        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cap.layer?.cornerRadius = 9
        cap.layer?.borderWidth = 1.5
        cap.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.widthAnchor.constraint(equalToConstant: 46).isActive = true
        cap.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let label = NSTextField(labelWithString: symbol)
        label.font = .systemFont(ofSize: 21, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        cap.addSubview(label)
        label.centerXAnchor.constraint(equalTo: cap.centerXAnchor).isActive = true
        label.centerYAnchor.constraint(equalTo: cap.centerYAnchor).isActive = true
        return cap
    }

    private func pulse(_ view: NSView, times: Int, interval: TimeInterval = 0.26,
                       then: @escaping () -> Void) {
        guard times > 0 else { then(); return }
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        springPop(view)
        after(0.12) { [weak self] in
            view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            self?.after(interval - 0.12) {
                self?.pulse(view, times: times - 1, interval: interval, then: then)
            }
        }
    }

    // A mini app window: traffic lights + title, returns the content area.
    private func makeMiniWindow(title: String, width: CGFloat, height: CGFloat) -> (window: NSView, content: NSView) {
        let win = NSView()
        win.wantsLayer = true
        win.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        win.layer?.cornerRadius = 10
        win.layer?.borderWidth = 1
        win.layer?.borderColor = NSColor.separatorColor.cgColor
        win.layer?.shadowOpacity = 0.25
        win.layer?.shadowRadius = 8
        win.layer?.shadowOffset = CGSize(width: 0, height: -3)
        win.translatesAutoresizingMaskIntoConstraints = false
        win.widthAnchor.constraint(equalToConstant: width).isActive = true
        win.heightAnchor.constraint(equalToConstant: height).isActive = true

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 5
        bar.translatesAutoresizingMaskIntoConstraints = false
        for color in [NSColor.systemRed, .systemYellow, .systemGreen] {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            bar.addArrangedSubview(dot)
        }
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        win.addSubview(bar)
        win.addSubview(titleLabel)
        win.addSubview(content)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: win.topAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: win.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: win.centerXAnchor),
            content.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: win.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: win.trailingAnchor, constant: -10),
            content.bottomAnchor.constraint(equalTo: win.bottomAnchor, constant: -8),
        ])
        return (win, content)
    }

    // MARK: - Scene 1: auto-fix

    private func sceneAutoFix(_ done: @escaping () -> Void) {
        let (text, field, pill) = makeMockField()
        after(0.4) { [weak self] in
            guard let self else { return }
            self.typeText("vhh nv bang", into: text) { [weak self] in
                guard let self else { return }
                self.after(0.5) {
                    self.convert(text, in: field, to: "היי מה נשמע",
                                 pill: pill, pillText: "עב") { done() }
                }
            }
        }
    }

    // MARK: - Scene 2: languages

    private func sceneLanguages(_ done: @escaping () -> Void) {
        // (garble, converted, pill) - each a true wrong-layout mapping.
        let rows: [(String, String, String)] = [
            ("ghbdtn",  "привет", "RU"),
            ("akuo",    "שלום",   "עב"),
            ("اثممخ",   "hello",  "EN"),
        ]
        var labels: [(NSTextField, NSTextField)] = []
        let column = NSStackView()
        column.orientation = .vertical
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        for (garble, _, pillText) in rows {
            let from = NSTextField(labelWithString: garble)
            from.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
            from.textColor = .secondaryLabelColor
            from.wantsLayer = true
            let arrow = NSTextField(labelWithString: "→")
            arrow.font = .systemFont(ofSize: 15, weight: .semibold)
            arrow.textColor = .tertiaryLabelColor
            let to = NSTextField(labelWithString: "")
            to.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
            to.wantsLayer = true
            let pill = makePill(pillText, active: false)
            let row = NSStackView(views: [from, arrow, to, NSView(), pill])
            row.orientation = .horizontal
            row.spacing = 12
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 330).isActive = true
            column.addArrangedSubview(row)
            labels.append((to, pill))
        }
        stage.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
        ])
        func flip(_ i: Int) {
            guard i < rows.count else { after(0.3) { done() }; return }
            let (_, converted, pillText) = rows[i]
            let (to, pill) = labels[i]
            to.stringValue = converted
            springPop(to)
            setPill(pill, to: pillText, active: true)
            after(0.75) { flip(i + 1) }
        }
        after(0.7) { flip(0) }
    }

    // MARK: - Scene 3: double-shift

    private func sceneDoubleShift(_ done: @escaping () -> Void) {
        let (text, field, pill) = makeMockField()
        text.stringValue = "rfr ltkf"
        let cap = makeKeycap("⇧")
        stage.addSubview(cap)
        cap.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -20).isActive = true
        cap.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -16).isActive = true
        after(0.6) { [weak self] in
            guard let self else { return }
            self.pulse(cap, times: 2) {
                self.convert(text, in: field, to: "как дела",
                             pill: pill, pillText: "RU") { done() }
            }
        }
    }

    // MARK: - Scene 4: haptics + sound

    private func sceneFeedback(_ done: @escaping () -> Void) {
        // A trackpad that ripples (the haptic tap) and a speaker that pulses with
        // the actual click sound the user has selected.
        let trackpad = NSView()
        trackpad.wantsLayer = true
        trackpad.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        trackpad.layer?.cornerRadius = 12
        trackpad.layer?.borderWidth = 1.5
        trackpad.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        trackpad.translatesAutoresizingMaskIntoConstraints = false
        trackpad.widthAnchor.constraint(equalToConstant: 130).isActive = true
        trackpad.heightAnchor.constraint(equalToConstant: 92).isActive = true
        let padLabel = NSTextField(labelWithString: "haptic tap")
        padLabel.font = .systemFont(ofSize: 10, weight: .medium)
        padLabel.textColor = .tertiaryLabelColor
        padLabel.translatesAutoresizingMaskIntoConstraints = false

        let speaker = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill",
                                                 accessibilityDescription: nil) ?? NSImage())
        speaker.symbolConfiguration = .init(pointSize: 40, weight: .medium)
        speaker.contentTintColor = .secondaryLabelColor
        speaker.wantsLayer = true
        speaker.translatesAutoresizingMaskIntoConstraints = false
        let speakerLabel = NSTextField(labelWithString: "your click sound")
        speakerLabel.font = .systemFont(ofSize: 10, weight: .medium)
        speakerLabel.textColor = .tertiaryLabelColor
        speakerLabel.translatesAutoresizingMaskIntoConstraints = false

        stage.addSubview(trackpad)
        stage.addSubview(padLabel)
        stage.addSubview(speaker)
        stage.addSubview(speakerLabel)
        NSLayoutConstraint.activate([
            trackpad.centerYAnchor.constraint(equalTo: stage.centerYAnchor, constant: -12),
            trackpad.centerXAnchor.constraint(equalTo: stage.centerXAnchor, constant: -105),
            padLabel.topAnchor.constraint(equalTo: trackpad.bottomAnchor, constant: 8),
            padLabel.centerXAnchor.constraint(equalTo: trackpad.centerXAnchor),
            speaker.centerYAnchor.constraint(equalTo: trackpad.centerYAnchor),
            speaker.centerXAnchor.constraint(equalTo: stage.centerXAnchor, constant: 105),
            speakerLabel.topAnchor.constraint(equalTo: speaker.bottomAnchor, constant: 12),
            speakerLabel.centerXAnchor.constraint(equalTo: speaker.centerXAnchor),
        ])

        // Expanding rings out of the trackpad center = the tap you feel.
        func ripple() {
            for delay in [0.0, 0.15] {
                after(delay) { [weak self] in
                    guard let self else { return }
                    let ring = NSView()
                    ring.wantsLayer = true
                    ring.layer?.borderColor = NSColor.controlAccentColor.cgColor
                    ring.layer?.borderWidth = 2
                    ring.layer?.cornerRadius = 22
                    ring.translatesAutoresizingMaskIntoConstraints = false
                    trackpad.addSubview(ring)
                    ring.widthAnchor.constraint(equalToConstant: 44).isActive = true
                    ring.heightAnchor.constraint(equalToConstant: 44).isActive = true
                    ring.centerXAnchor.constraint(equalTo: trackpad.centerXAnchor).isActive = true
                    ring.centerYAnchor.constraint(equalTo: trackpad.centerYAnchor).isActive = true
                    let grow = CABasicAnimation(keyPath: "transform.scale")
                    grow.fromValue = 0.3; grow.toValue = 1.9
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 1; fade.toValue = 0
                    let group = CAAnimationGroup()
                    group.animations = [grow, fade]
                    group.duration = 0.7
                    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    ring.layer?.add(group, forKey: "ripple")
                    self.after(0.7) { ring.removeFromSuperview() }
                }
            }
            springPop(trackpad)
        }

        after(0.7) { [weak self] in
            guard let self else { return }
            ripple()
            self.after(0.5) {
                // The speaker moment plays the user's ACTUAL selected click.
                speaker.contentTintColor = .controlAccentColor
                self.springPop(speaker)
                SoundEffect.preview(SoundEffect.selected)
                self.after(0.8) {
                    speaker.contentTintColor = .secondaryLabelColor
                    ripple()
                    self.after(0.9) { done() }
                }
            }
        }
    }

    // MARK: - Scene 5: memory (browser tabs + chats)

    private func sceneMemory(_ done: @escaping () -> Void) {
        // A mini browser (two tabs) and a mini chat window (two conversations).
        // A focus ring visits tab -> tab -> chat -> chat; the pill follows.
        let (browser, browserContent) = makeMiniWindow(title: "Browser", width: 225, height: 120)
        let (chat, chatContent) = makeMiniWindow(title: "Teams / Slack", width: 225, height: 120)

        // Browser tabs
        func tab(_ title: String) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.cornerRadius = 6
            view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15).cgColor
            view.layer?.borderWidth = 1.5
            view.layer?.borderColor = NSColor.clear.cgColor
            view.translatesAutoresizingMaskIntoConstraints = false
            view.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            return view
        }
        let tabA = tab("docs.google.com")
        let tabB = tab("ynet.co.il")
        let tabRow = NSStackView(views: [tabA, tabB])
        tabRow.orientation = .horizontal
        tabRow.spacing = 6
        tabRow.distribution = .fillEqually
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        let page = NSView()
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        page.layer?.cornerRadius = 6
        page.translatesAutoresizingMaskIntoConstraints = false
        browserContent.addSubview(tabRow)
        browserContent.addSubview(page)
        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: browserContent.topAnchor),
            tabRow.leadingAnchor.constraint(equalTo: browserContent.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: browserContent.trailingAnchor),
            page.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: 6),
            page.leadingAnchor.constraint(equalTo: browserContent.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: browserContent.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: browserContent.bottomAnchor),
        ])

        // Chat rows
        func chatRow(_ name: String, tint: NSColor) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.cornerRadius = 6
            view.layer?.borderWidth = 1.5
            view.layer?.borderColor = NSColor.clear.cgColor
            view.translatesAutoresizingMaskIntoConstraints = false
            view.heightAnchor.constraint(equalToConstant: 30).isActive = true
            let avatar = NSView()
            avatar.wantsLayer = true
            avatar.layer?.backgroundColor = tint.withAlphaComponent(0.7).cgColor
            avatar.layer?.cornerRadius = 9
            avatar.translatesAutoresizingMaskIntoConstraints = false
            avatar.widthAnchor.constraint(equalToConstant: 18).isActive = true
            avatar.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(avatar)
            view.addSubview(label)
            avatar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6).isActive = true
            avatar.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            label.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8).isActive = true
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            return view
        }
        let chatA = chatRow("Design team", tint: .systemTeal)
        let chatB = chatRow("אמא", tint: .systemPink)
        let chatColumn = NSStackView(views: [chatA, chatB])
        chatColumn.orientation = .vertical
        chatColumn.spacing = 6
        chatColumn.translatesAutoresizingMaskIntoConstraints = false
        chatContent.addSubview(chatColumn)
        NSLayoutConstraint.activate([
            chatColumn.topAnchor.constraint(equalTo: chatContent.topAnchor),
            chatColumn.leadingAnchor.constraint(equalTo: chatContent.leadingAnchor),
            chatColumn.trailingAnchor.constraint(equalTo: chatContent.trailingAnchor),
        ])

        let pill = makePill("ABC", active: false)
        stage.addSubview(browser)
        stage.addSubview(chat)
        stage.addSubview(pill)
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 18),
            browser.topAnchor.constraint(equalTo: stage.topAnchor, constant: 16),
            chat.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -18),
            chat.topAnchor.constraint(equalTo: stage.topAnchor, constant: 16),
            pill.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -14),
        ])

        // Focus walk: docs tab (EN) -> ynet tab (HE) -> Design team (EN) -> אמא (HE)
        let stops: [(NSView, String, Bool)] = [
            (tabA, "ABC", false), (tabB, "עב", true),
            (chatA, "ABC", false), (chatB, "עב", true),
        ]
        let highlightable = [tabA, tabB, chatA, chatB]
        func visit(_ i: Int) {
            guard i < stops.count else { after(0.3) { done() }; return }
            let (view, pillText, active) = stops[i]
            for h in highlightable {
                h.layer?.borderColor = (h === view ? NSColor.controlAccentColor : NSColor.clear).cgColor
            }
            springPop(view)
            setPill(pill, to: pillText, active: active)
            after(0.95) { visit(i + 1) }
        }
        after(0.5) { visit(0) }
    }

    private func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }
}
