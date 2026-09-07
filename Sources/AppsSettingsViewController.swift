import AppKit

// The "Apps" settings tab: lists each app and the keyboard input it forces.
// Each row has an input-source popup; users can add apps by name or by browsing.
// Browsers show an AUTO (per-site) option. Reads/writes AppRules.
// (Ported from the former standalone "Preferred Input per App" window.)
final class AppsSettingsViewController: NSViewController, NSTextFieldDelegate {

    private let listStack = HoverStackView()
    private weak var searchField: NSTextField?
    private weak var contentRoot: NSView?
    private var suggestionList: SuggestionListView?
    private var browserCatalogToken: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        browserCatalogToken = NotificationCenter.default.addObserver(
            forName: .browserCatalogChanged, object: nil, queue: .main) { [weak self] _ in
                self?.buildRows()
            }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        buildRows()
    }

    deinit {
        if let browserCatalogToken { NotificationCenter.default.removeObserver(browserCatalogToken) }
    }

    override func loadView() {
        let title = NSTextField(labelWithString: "Preferred Input per App")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Type an app name to add it, or tap + to browse.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let search = NSTextField()
        search.placeholderString = "Add app by name…"
        search.delegate = self
        searchField = search
        search.font = .systemFont(ofSize: 13)
        search.bezelStyle = .roundedBezel
        search.target = self
        search.action = #selector(addByName(_:))

        let browse = NSButton(image: NSImage(systemSymbolName: "plus",
                                             accessibilityDescription: "Browse")!,
                              target: self, action: #selector(browseForApp))
        browse.bezelStyle = .rounded
        browse.toolTip = "Choose an app in Finder"
        browse.setContentHuggingPriority(.required, for: .horizontal)

        let addBar = NSStackView(views: [search, browse])
        addBar.orientation = .horizontal
        addBar.spacing = 8

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 2
        listStack.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 16, right: 16)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = listStack
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: clip.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            listStack.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        for v in [title, subtitle, addBar, scroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: settingsContentWidth),
            container.heightAnchor.constraint(equalToConstant: 640),

            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            addBar.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            addBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            addBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: addBar.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        buildRows()
        contentRoot = container
        view = container
        preferredContentSize = NSSize(width: settingsContentWidth, height: 640)
    }

    private func buildRows() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let normal = AppRules.editable.filter { $0.kind == .normal }
        let conversation = AppRules.editable.filter { $0.kind == .conversation }
        let browsers = AppRules.editable.filter { $0.kind == .browser }

        for app in normal { addRow(for: app) }

        if !conversation.isEmpty {
            addSectionHeaderRow("Chat apps")
            for app in conversation { addRow(for: app) }
        }
        if !browsers.isEmpty {
            addSectionHeaderRow("Browsers")
            for app in browsers { addRow(for: app) }
        }

        let footnote = NSTextField(wrappingLabelWithString:
            "AUTO learns and remembers the input language automatically - per website "
            + "for browsers, per conversation for chat apps. Pick a language instead to "
            + "force it. Apps not listed keep whatever input was last active.")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        listStack.addArrangedSubview(spacer(12))
        listStack.addArrangedSubview(footnote)
        footnote.widthAnchor.constraint(
            equalTo: listStack.widthAnchor,
            constant: -listStack.edgeInsets.left - listStack.edgeInsets.right
        ).isActive = true
    }

    private func addRow(for app: AppRule) {
        let row = RuleRowView(
            app: app,
            onSetRule: { rule in AppRules.setRule(rule, for: app) },
            onRemove: { [weak self] in
                AppRules.remove(app)
                self?.buildRows()
            }
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        listStack.addArrangedSubview(row)
        row.widthAnchor.constraint(
            equalTo: listStack.widthAnchor,
            constant: -listStack.edgeInsets.left - listStack.edgeInsets.right
        ).isActive = true
    }

    private func addSectionHeaderRow(_ title: String) {
        listStack.addArrangedSubview(spacer(10))
        listStack.addArrangedSubview(sectionHeader(title))
        listStack.addArrangedSubview(spacer(2))
    }

    // MARK: - Live suggestions

    func controlTextDidChange(_ obj: Notification) { updateSuggestions() }

    private func updateSuggestions() {
        guard let field = searchField, let root = contentRoot else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        let matches = query.count >= 3 ? AppFinder.search(query) : []

        guard !matches.isEmpty else { closeSuggestions(); return }

        let list = suggestionList ?? {
            let l = SuggestionListView()
            root.addSubview(l)
            suggestionList = l
            return l
        }()
        list.onPick = { [weak self] url in
            self?.closeSuggestions()
            self?.add(url: url, clearing: self?.searchField)
        }
        let height = list.setItems(matches)

        let fieldRect = root.convert(field.bounds, from: field)
        list.frame = NSRect(x: fieldRect.minX, y: fieldRect.minY - height - 4,
                            width: fieldRect.width, height: height)
    }

    private func closeSuggestions() {
        suggestionList?.removeFromSuperview()
        suggestionList = nil
    }

    // MARK: - Adding apps

    @objc private func addByName(_ sender: NSTextField) {
        closeSuggestions()
        let query = sender.stringValue
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let url = AppFinder.find(named: query) else {
            Overlay.show("No app named “\(query)”", symbol: "questionmark.circle")
            return
        }
        add(url: url, clearing: sender)
    }

    @objc private func browseForApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            add(url: url, clearing: nil)
        }
    }

    private func add(url: URL, clearing field: NSTextField?) {
        let info = AppFinder.info(at: url)
        if AppRules.addCustom(info) {
            field?.stringValue = ""
            buildRows()
            Overlay.show("Added \(info.name)", symbol: "checkmark.circle")
        } else {
            Overlay.show("\(info.name) is already listed", symbol: "info.circle")
        }
    }
}

// MARK: - Hovering list

// A vertical stack that highlights the row under the cursor and recomputes that
// highlight while scrolling, so rows don't get stuck lit.
private final class HoverStackView: NSStackView {

    // The rule rows among the arranged subviews (which also hold section headers,
    // a spacer, and the footnote). Derived so there's no parallel list to keep in
    // sync as rows are added or removed.
    private var rows: [RuleRowView] { arrangedSubviews.compactMap { $0 as? RuleRowView } }
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // viewDidMoveToWindow can fire repeatedly (the tab view swaps this view
        // out/in as tabs change). Remove any prior registration before re-adding
        // so observers don't stack up and fire scrolled() N times.
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: clip)
    }

    override func mouseMoved(with event: NSEvent) { hover(at: point(from: event)) }
    override func mouseEntered(with event: NSEvent) { hover(at: point(from: event)) }
    override func mouseExited(with event: NSEvent) { rows.forEach { $0.setHighlighted(false) } }

    @objc private func scrolled() {
        guard let window else { return }
        hover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func point(from event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }

    private func hover(at point: NSPoint) {
        for row in rows { row.setHighlighted(row.frame.contains(point)) }
    }
}

// MARK: - Row

private final class RuleRowView: NSView {

    private let appName: String
    private let onSetRule: (InputRule) -> Void
    private let onRemove: () -> Void
    private let popup = NSPopUpButton()
    private var itemRules: [InputRule] = []

    init(app: AppRule, onSetRule: @escaping (InputRule) -> Void, onRemove: @escaping () -> Void) {
        self.appName = app.name
        self.onSetRule = onSetRule
        self.onRemove = onRemove
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8

        let icon = NSImageView()
        icon.image = Self.resolveIcon(for: app)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let name = NSTextField(labelWithString: app.name)
        name.font = .systemFont(ofSize: 13)

        for source in InputSourceCatalog.enabledSources() {
            popup.addItem(withTitle: source.localizedName)
            itemRules.append(.source(source.id))
        }
        switch app.kind {
        case .browser:
            popup.addItem(withTitle: "Auto (per-site)")
            itemRules.append(.auto)
        case .conversation:
            popup.addItem(withTitle: "Auto (per-conversation)")
            itemRules.append(.auto)
        case .normal:
            break
        }
        // The stored rule can reference an input source the user has since disabled,
        // so it may not be among the enabled sources listed above. Show it explicitly
        // and select it, rather than falling back to the first source while the stale
        // rule silently stays in effect.
        if let index = itemRules.firstIndex(of: app.rule) {
            popup.selectItem(at: index)
        } else {
            popup.addItem(withTitle: Self.unavailableRuleTitle(app.rule))
            itemRules.append(app.rule)
            popup.selectItem(at: itemRules.count - 1)
        }
        popup.target = self
        popup.action = #selector(ruleChanged)
        popup.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, name, NSView(), popup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // Title for a stored rule that isn't currently selectable, e.g. a forced source
    // whose layout the user has since removed in System Settings.
    private static func unavailableRuleTitle(_ rule: InputRule) -> String {
        switch rule {
        case .auto:
            return "Auto"
        case .source(let id):
            let name = InputSourceCatalog.localizedName(for: id) ?? id
            return "\(name) (not enabled)"
        }
    }

    @objc private func ruleChanged() {
        let index = popup.indexOfSelectedItem
        guard itemRules.indices.contains(index) else { return }
        onSetRule(itemRules[index])
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Remove \(appName)",
                              action: #selector(removeTapped), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func removeTapped() { onRemove() }

    func setHighlighted(_ on: Bool) {
        layer?.backgroundColor = on
            ? NSColor.labelColor.withAlphaComponent(0.10).cgColor
            : NSColor.clear.cgColor
    }

    static func resolveIcon(for app: AppRule) -> NSImage {
        let workspace = NSWorkspace.shared
        if !app.bundleID.isEmpty,
           let url = workspace.urlForApplication(withBundleIdentifier: app.bundleID) {
            return workspace.icon(forFile: url.path)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let symbol = NSImage(systemSymbolName: app.rule.fallbackSymbol, accessibilityDescription: nil)
        return symbol?.withSymbolConfiguration(config) ?? NSImage()
    }
}

// MARK: - Suggestions dropdown

private final class SuggestionListView: NSView {

    var onPick: ((URL) -> Void)?
    private let stack = NSStackView()
    private let rowHeight: CGFloat = 28
    private let inset: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = NSShadow()
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setItems(_ items: [AppMatch]) -> CGFloat {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for match in items {
            let icon = NSWorkspace.shared.icon(forFile: match.url.path)
            let row = SuggestionRow(match: match, icon: icon) { [weak self] in
                self?.onPick?(match.url)
            }
            stack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return CGFloat(items.count) * rowHeight + inset * 2
    }
}

private final class SuggestionRow: NSView {

    private let action: () -> Void
    private var trackingArea: NSTrackingArea?

    init(match: AppMatch, icon: NSImage, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5

        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let name = NSTextField(labelWithString: match.name)
        name.font = .systemFont(ofSize: 13)

        var views: [NSView] = [iconView, name, NSView()]
        if let location = match.location {
            let loc = NSTextField(labelWithString: location)
            loc.font = .systemFont(ofSize: 11)
            loc.textColor = .secondaryLabelColor
            views.append(loc)
        }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { action() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        NSCursor.arrow.set()
    }
}
