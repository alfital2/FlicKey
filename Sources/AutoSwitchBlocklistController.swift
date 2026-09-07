import AppKit

// A small sheet listing the words the user has taught auto-switch to leave alone,
// with per-word removal and a clear-all. Reachable from the General → Typing pane
// so a word blocked by mistake (e.g. an accidental double undo) is visible and
// recoverable — important for a public-source release where nothing should be a
// silent, unremovable decision.
final class AutoSwitchBlocklistController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private let exceptions = AutoSwitchExceptions()
    private var words: [String] = []
    private var panel: NSPanel?
    private weak var table: NSTableView?
    private weak var emptyLabel: NSTextField?
    private weak var removeButton: NSButton?

    func present(from parent: NSWindow?) {
        words = exceptions.blockedWords()

        // Already open: refresh its data and bring it forward. Building a second
        // panel would leave the first on screen with its controls silently acting
        // on the new panel's table.
        if let existing = panel {
            table?.reloadData()
            refreshEmptyState()
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Blocked Words"
        // Keep the instance alive across a title-bar close so present() can safely
        // re-show it (the reuse path above) instead of stacking a second panel.
        panel.isReleasedWhenClosed = false
        self.panel = panel

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 22
        let column = NSTableColumn(identifier: .init("word"))
        column.width = 320
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.target = self
        scroll.documentView = table
        self.table = table

        let empty = NSTextField(labelWithString: "No blocked words. FlicKey learns one after you undo its fix for the same word twice.")
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.maximumNumberOfLines = 3
        empty.lineBreakMode = .byWordWrapping
        self.emptyLabel = empty

        let remove = NSButton(title: "Remove", target: self, action: #selector(removeSelected))
        remove.bezelStyle = .rounded
        remove.isEnabled = false
        self.removeButton = remove
        let clear = NSButton(title: "Clear All", target: self, action: #selector(clearAll))
        clear.bezelStyle = .rounded
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [remove, clear, NSView(), done])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [scroll, empty, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
        refreshEmptyState()
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func refreshEmptyState() {
        table?.enclosingScrollView?.isHidden = words.isEmpty
        emptyLabel?.isHidden = !words.isEmpty
        removeButton?.isEnabled = !words.isEmpty && (table?.selectedRow ?? -1) >= 0
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { words.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField)
            ?? { let f = NSTextField(labelWithString: ""); f.identifier = id; return f }()
        field.stringValue = words[row]
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton?.isEnabled = (table?.selectedRow ?? -1) >= 0
    }

    // MARK: - Actions

    @objc private func removeSelected() {
        guard let row = table?.selectedRow, words.indices.contains(row) else { return }
        exceptions.unblock(words[row])
        words.remove(at: row)
        table?.reloadData()
        // reloadData keeps the old row index selected — now the NEXT word — with
        // Remove still enabled, so a fast second click would silently unblock the
        // neighbor. Clear the selection and require a fresh pick.
        table?.deselectAll(nil)
        removeButton?.isEnabled = false
        refreshEmptyState()
    }

    @objc private func clearAll() {
        exceptions.clearAll()
        words = []
        table?.reloadData()
        refreshEmptyState()
    }

    @objc private func close() {
        panel?.close()
        panel = nil
    }
}
