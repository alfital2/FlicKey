import AppKit

// Settings → Support: trial/license status, the "free forever" promise, license
// activation, and the Support (buy) button.
final class LicenseSettingsViewController: NSViewController {

    private let statusField = NSTextField(wrappingLabelWithString: "")
    private let promiseField = NSTextField(wrappingLabelWithString: "")
    private let keyField = NSTextField(string: "")
    private let activateButton = NSButton(title: "Activate", target: nil, action: nil)
    private let buyButton = NSButton(title: "Support FlicKey", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove License", target: nil, action: nil)
    private var entryRow: NSStackView!

    override func loadView() {
        let header = sectionHeader("Support")

        statusField.font = .systemFont(ofSize: 13)
        statusField.setAccessibilityIdentifier("licenseStatus")

        // The reassurance shown before purchase — set per entitlement in refresh().
        promiseField.font = .systemFont(ofSize: 12)
        promiseField.textColor = .secondaryLabelColor

        keyField.placeholderString = "Paste your license key…"
        keyField.setAccessibilityIdentifier("licenseKeyField")
        keyField.widthAnchor.constraint(equalToConstant: 320).isActive = true

        activateButton.target = self; activateButton.action = #selector(activate)
        activateButton.bezelStyle = .rounded
        activateButton.setAccessibilityIdentifier("activateLicense")

        buyButton.target = self; buyButton.action = #selector(buy); buyButton.bezelStyle = .rounded
        buyButton.setAccessibilityIdentifier("buyLicense")
        removeButton.target = self; removeButton.action = #selector(remove); removeButton.bezelStyle = .rounded

        entryRow = NSStackView(views: [keyField, activateButton])
        entryRow.orientation = .horizontal; entryRow.spacing = 8

        let actionRow = NSStackView(views: [buyButton, removeButton])
        actionRow.orientation = .horizontal; actionRow.spacing = 10

        let tourButton = NSButton(title: "Show the Welcome Tour",
                                  target: self, action: #selector(showTour))
        tourButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            header, statusField, promiseField,
            spacer(8), entryRow, actionRow,
            spacer(8), tourButton,
        ])
        // Fixed height: refresh() hides or shows the promise, entry, and buttons
        // depending on license state, so a content-sized pane would jump around.
        installSettingsPane(stack, cards: [], spacing: 10, fixedHeight: 320)
    }

    override func viewWillAppear() { super.viewWillAppear(); refresh() }

    private func refresh() {
        // Show the truth for THIS user's entitlement: grandfathered users keep the
        // free-forever promise; new users see the trial countdown and, after it,
        // the unlock. A real license always shows as licensed.
        switch Entitlement.current() {
        case .licensed:
            let who = LicenseStore.current.map { " to \($0.name) (\($0.email))" } ?? ""
            statusField.stringValue = "✓ FlicKey is unlocked\(who).\nThank you for supporting FlicKey 💙"
            promiseField.isHidden = true
            entryRow.isHidden = true
            buyButton.isHidden = true
            removeButton.isHidden = (LicenseStore.current == nil)

        case .grandfathered:
            statusField.stringValue = "You have FlicKey free, forever."
            promiseField.stringValue =
                "As an early user, every feature stays free for you, forever - even if you never buy. "
                + "A license is simply an optional way to support the project and fund new updates. 💙"
            buyButton.title = "Support FlicKey"
            showPurchaseControls()

        case .trial(let daysLeft):
            let unit = daysLeft == 1 ? "day" : "days"
            statusField.stringValue = "Free trial - \(daysLeft) \(unit) left."
            promiseField.stringValue =
                "Your 30-day free trial includes every feature. After it ends, a one-time purchase keeps "
                + "automatic switching and conversion working - no subscription, no account. 💙"
            buyButton.title = "Unlock FlicKey"
            showPurchaseControls()

        case .expired:
            statusField.stringValue = "Your free trial has ended."
            promiseField.stringValue =
                "Unlock FlicKey with a one-time purchase to bring back automatic switching and conversion. "
                + "Everything else keeps working. 💙"
            buyButton.title = "Unlock FlicKey"
            showPurchaseControls()
        }
    }

    private func showPurchaseControls() {
        promiseField.isHidden = false
        entryRow.isHidden = false
        buyButton.isHidden = false
        removeButton.isHidden = true
    }

    @objc private func showTour() {
        WelcomeTourController.shared.present()
    }

    @objc private func activate() {
        let key = keyField.stringValue
        activateButton.isEnabled = false
        statusField.stringValue = "Checking your license…"
        Task { @MainActor in
            let result = await LicenseStore.activate(key)
            activateButton.isEnabled = true
            switch result {
            case .success(let record):
                keyField.stringValue = ""
                Overlay.show("License activated - thank you, \(record.name)!", symbol: "checkmark.seal.fill")
            case .failure(let message):
                Overlay.show(message, symbol: "xmark.seal")
            }
            refresh()
        }
    }

    @objc private func buy() { NSWorkspace.shared.open(LicenseStore.buyURL) }

    @objc private func remove() { LicenseStore.deactivate(); refresh() }
}
