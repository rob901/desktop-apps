import AppKit
import DesktopKit

/// The stickies rows in the framework's preferences window.
final class NotePreferencesPane: NSObject, PreferencesPane {
    private let colorPopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let fontSizeField = NSTextField()
    private let fontSizeStepper = NSStepper()
    private let textColorWell = NSColorWell()
    private let preview = NSView()
    private let previewText = NSTextField(labelWithString: "The quick brown fox")
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let notePopup = NSPopUpButton()
    private let useSizeButton = NSButton()
    private let usedLabel = NSTextField(labelWithString: "")

    // MARK: PreferencesPane

    func refresh() {
        let c = NotePrefs.color
        colorPopup.selectItem(at: NoteColor.allCases.firstIndex(of: c) ?? 0)
        if fontPopup.item(withTitle: NotePrefs.fontFamily) == nil { fontPopup.addItem(withTitle: NotePrefs.fontFamily) }
        fontPopup.selectItem(withTitle: NotePrefs.fontFamily)
        fontSizeField.integerValue = Int(NotePrefs.fontSize)
        fontSizeStepper.integerValue = Int(NotePrefs.fontSize)
        textColorWell.color = NotePrefs.textColor
        widthField.integerValue = Int(NotePrefs.size.width)
        heightField.integerValue = Int(NotePrefs.size.height)
        rebuildNoteList()
        updatePreview()
    }

    func preferencesDidBecomeKey() { rebuildNoteList() }

    func build(_ form: PreferencesForm) {
        typealias F = PreferencesForm

        for c in NoteColor.allCases {
            colorPopup.addItem(withTitle: c.title)
            colorPopup.lastItem?.image = c.swatch()
        }
        target(colorPopup, #selector(colorChanged))

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        target(fontPopup, #selector(fontChanged))

        F.numberField(fontSizeField, target: self, action: #selector(fontSizeFieldChanged), width: 44)
        fontSizeStepper.minValue = 8
        fontSizeStepper.maxValue = 72
        fontSizeStepper.increment = 1
        fontSizeStepper.valueWraps = false
        target(fontSizeStepper, #selector(fontSizeStepperChanged))
        let fontRow = F.hstack([fontPopup, fontSizeField, fontSizeStepper, F.label("pt")])
        fontPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        target(textColorWell, #selector(textColorChanged))
        textColorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        textColorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        preview.wantsLayer = true
        preview.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        preview.layer?.borderWidth = 0.5
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewText.translatesAutoresizingMaskIntoConstraints = false
        previewText.lineBreakMode = .byTruncatingTail
        preview.addSubview(previewText)
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 260),
            preview.heightAnchor.constraint(equalToConstant: 54),
            previewText.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 8),
            previewText.trailingAnchor.constraint(lessThanOrEqualTo: preview.trailingAnchor, constant: -8),
            previewText.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
        ])

        F.numberField(widthField, target: self, action: #selector(sizeChanged), width: 56)
        F.numberField(heightField, target: self, action: #selector(sizeChanged), width: 56)
        let sizeRow = F.hstack([widthField, F.label("×"), heightField, F.label("pt   (width × height)")])

        notePopup.widthAnchor.constraint(equalToConstant: 260).isActive = true
        useSizeButton.title = "Use This Note's Size"
        useSizeButton.bezelStyle = .rounded
        target(useSizeButton, #selector(useNoteSize))
        usedLabel.textColor = .secondaryLabelColor
        let useRow = F.hstack([notePopup, useSizeButton, usedLabel])

        form.addRow("New note color:", colorPopup)
        form.addRow("Font:", fontRow)
        form.addRow("Text color:", textColorWell, alignment: .center)
        form.addRow("Preview:", preview, alignment: .center)
        form.addRow("New note size:", sizeRow, topPadding: 12)
        form.addRow(nil, useRow)
        form.addHint("Notes are listed by their first line, the same text the bar shows when a note is collapsed.")
        form.addSnappingRow(itemName: "notes")
    }

    // MARK: Updating

    private func rebuildNoteList() {
        let selectedID = notePopup.selectedItem?.representedObject as? UUID
        notePopup.removeAllItems()
        let notes = StickiesApp.shared.notes
        for (i, note) in notes.enumerated() {
            let s = note.expandedSize
            let name = note.firstLine.map { String($0.prefix(40)) } ?? "Untitled note \(i + 1)"
            notePopup.addItem(withTitle: "\(name)  —  \(Int(s.width))×\(Int(s.height))")
            notePopup.lastItem?.representedObject = note.id
            notePopup.lastItem?.image = note.color.swatch()
        }
        if notes.isEmpty {
            notePopup.addItem(withTitle: "No notes")
        } else if let selectedID, let index = notes.firstIndex(where: { $0.id == selectedID }) {
            notePopup.selectItem(at: index)
        }
        notePopup.isEnabled = !notes.isEmpty
        useSizeButton.isEnabled = !notes.isEmpty
    }

    private func updatePreview() {
        preview.layer?.backgroundColor = NotePrefs.color.body.cgColor
        previewText.font = NotePrefs.font
        previewText.textColor = NotePrefs.textColor
    }

    // MARK: Actions

    @objc private func colorChanged() {
        NotePrefs.color = NoteColor.allCases[max(0, colorPopup.indexOfSelectedItem)]
        updatePreview()
    }

    @objc private func fontChanged() {
        if let family = fontPopup.titleOfSelectedItem { NotePrefs.fontFamily = family }
        updatePreview()
    }

    @objc private func fontSizeFieldChanged() {
        let v = min(72, max(8, fontSizeField.integerValue))
        NotePrefs.fontSize = CGFloat(v)
        fontSizeField.integerValue = v
        fontSizeStepper.integerValue = v
        updatePreview()
    }

    @objc private func fontSizeStepperChanged() {
        fontSizeField.integerValue = fontSizeStepper.integerValue
        fontSizeFieldChanged()
    }

    @objc private func textColorChanged() {
        NotePrefs.textColor = textColorWell.color
        updatePreview()
    }

    @objc private func sizeChanged() {
        NotePrefs.size = NSSize(width: widthField.integerValue, height: heightField.integerValue)
        widthField.integerValue = Int(NotePrefs.size.width)
        heightField.integerValue = Int(NotePrefs.size.height)
    }

    @objc private func useNoteSize() {
        guard let id = notePopup.selectedItem?.representedObject as? UUID,
              let note = StickiesApp.shared.notes.first(where: { $0.id == id }) else { return }
        NotePrefs.size = note.expandedSize
        widthField.integerValue = Int(NotePrefs.size.width)
        heightField.integerValue = Int(NotePrefs.size.height)
        usedLabel.stringValue = "✓ Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.usedLabel.stringValue = "" }
    }

    private func target(_ control: NSControl, _ action: Selector) {
        control.target = self
        control.action = action
    }
}
