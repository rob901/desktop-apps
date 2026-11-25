import AppKit
import DesktopKit

/// Claude Usage rows in the framework's preferences window.
final class UsagePreferencesPane: NSObject, PreferencesPane {
    private let warningField = NSTextField()
    private let criticalField = NSTextField()
    private let pathLabel = NSTextField(labelWithString: "")

    func build(_ form: PreferencesForm) {
        typealias F = PreferencesForm
        F.numberField(warningField, target: self, action: #selector(levelsChanged), width: 44)
        F.numberField(criticalField, target: self, action: #selector(levelsChanged), width: 44)
        form.addRow("Amber at:", F.hstack([warningField, F.label("%")]))
        form.addRow("Red at:", F.hstack([criticalField, F.label("%")]))
        form.addHint("The session and weekly meters change color, and show a warning icon, at these levels.")

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let reveal = NSButton(title: "Show in Finder", target: self, action: #selector(revealFile))
        reveal.bezelStyle = .rounded
        reveal.controlSize = .small
        form.addRow("Usage data:", F.hstack([pathLabel, reveal]), topPadding: 12)
        form.addHint("Read from the Claude desktop app, which records your plan usage every few minutes while it's running. "
                     + "Gaps in the chart are times it wasn't running.")

        form.addSnappingRow(itemName: "widgets")
    }

    func refresh() {
        warningField.integerValue = UsageSettings.warningLevel
        criticalField.integerValue = UsageSettings.criticalLevel
        let path = UsageApp.shared.source.url.path
        pathLabel.stringValue = (path as NSString).abbreviatingWithTildeInPath
        pathLabel.toolTip = path
    }

    @objc private func levelsChanged() {
        UsageSettings.warningLevel = warningField.integerValue
        UsageSettings.criticalLevel = max(criticalField.integerValue, UsageSettings.warningLevel + 1)
        refresh()
        UsageApp.shared.refreshDisplay()
    }

    @objc private func revealFile() {
        let url = UsageApp.shared.source.url
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
