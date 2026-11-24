import AppKit

/// Preferences window. Unlike the notes, this is an ordinary window: opening it
/// brings the app forward (which ends Show Desktop, as any app would).
final class PrefsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return performStandardEditShortcut(event, from: self) || super.performKeyEquivalent(with: event)
    }
}

final class PreferencesController: NSObject, NSWindowDelegate {
    static let shared = PreferencesController()

    private var window: PrefsWindow?

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
    private let snapCheckbox = NSButton()

    // MARK: Showing

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Called when notes are added or removed, or a note's size is used as the default.
    func notesChanged() {
        guard let window, window.isVisible else { return }
        refresh()
    }

    private func refresh() {
        let c = Prefs.color
        colorPopup.selectItem(at: NoteColor.allCases.firstIndex(of: c) ?? 0)
        if fontPopup.item(withTitle: Prefs.fontFamily) == nil { fontPopup.addItem(withTitle: Prefs.fontFamily) }
        fontPopup.selectItem(withTitle: Prefs.fontFamily)
        fontSizeField.integerValue = Int(Prefs.fontSize)
        fontSizeStepper.integerValue = Int(Prefs.fontSize)
        textColorWell.color = Prefs.textColor
        widthField.integerValue = Int(Prefs.size.width)
        heightField.integerValue = Int(Prefs.size.height)
        snapCheckbox.state = Prefs.snapping ? .on : .off
        rebuildNoteList()
        updatePreview()
    }

    private func rebuildNoteList() {
        let selectedID = notePopup.selectedItem?.representedObject as? UUID
        notePopup.removeAllItems()
        let notes = AppDelegate.shared.notes
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
        preview.layer?.backgroundColor = Prefs.color.body.cgColor
        previewText.font = Prefs.font
        previewText.textColor = Prefs.textColor
    }

    // MARK: Actions

    @objc private func colorChanged() {
        Prefs.color = NoteColor.allCases[max(0, colorPopup.indexOfSelectedItem)]
        updatePreview()
    }

    @objc private func fontChanged() {
        if let family = fontPopup.titleOfSelectedItem { Prefs.fontFamily = family }
        updatePreview()
    }

    @objc private func fontSizeFieldChanged() {
        let v = min(72, max(8, fontSizeField.integerValue))
        Prefs.fontSize = CGFloat(v)
        fontSizeField.integerValue = v
        fontSizeStepper.integerValue = v
        updatePreview()
    }

    @objc private func fontSizeStepperChanged() {
        fontSizeField.integerValue = fontSizeStepper.integerValue
        fontSizeFieldChanged()
    }

    @objc private func textColorChanged() {
        Prefs.textColor = textColorWell.color
        updatePreview()
    }

    @objc private func sizeChanged() {
        Prefs.size = NSSize(width: widthField.integerValue, height: heightField.integerValue)
        widthField.integerValue = Int(Prefs.size.width)
        heightField.integerValue = Int(Prefs.size.height)
    }

    @objc private func useNoteSize() {
        guard let id = notePopup.selectedItem?.representedObject as? UUID,
              let note = AppDelegate.shared.notes.first(where: { $0.id == id }) else { return }
        Prefs.size = note.expandedSize
        widthField.integerValue = Int(Prefs.size.width)
        heightField.integerValue = Int(Prefs.size.height)
        usedLabel.stringValue = "✓ Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.usedLabel.stringValue = "" }
    }

    @objc private func snapChanged() {
        Prefs.snapping = snapCheckbox.state == .on
    }

    func windowDidBecomeKey(_ notification: Notification) { rebuildNoteList() }

    func windowWillClose(_ notification: Notification) {
        // Commit a number that's still being typed.
        window?.makeFirstResponder(nil)
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
    }

    // MARK: Building the window

    private func build() {
        for c in NoteColor.allCases {
            colorPopup.addItem(withTitle: c.title)
            colorPopup.lastItem?.image = c.swatch()
        }
        target(colorPopup, #selector(colorChanged))

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        target(fontPopup, #selector(fontChanged))

        numberField(fontSizeField, #selector(fontSizeFieldChanged), width: 44)
        fontSizeStepper.minValue = 8
        fontSizeStepper.maxValue = 72
        fontSizeStepper.increment = 1
        fontSizeStepper.valueWraps = false
        target(fontSizeStepper, #selector(fontSizeStepperChanged))
        let fontRow = row([fontPopup, fontSizeField, fontSizeStepper, label("pt")])
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

        numberField(widthField, #selector(sizeChanged), width: 56)
        numberField(heightField, #selector(sizeChanged), width: 56)
        let sizeRow = row([widthField, label("×"), heightField, label("pt   (width × height)")])

        notePopup.widthAnchor.constraint(equalToConstant: 260).isActive = true
        useSizeButton.title = "Use This Note's Size"
        useSizeButton.bezelStyle = .rounded
        target(useSizeButton, #selector(useNoteSize))
        usedLabel.textColor = .secondaryLabelColor
        let useRow = row([notePopup, useSizeButton, usedLabel])
        let useHint = hint("Notes are listed by their first line, the same text the bar shows when a note is collapsed.")

        snapCheckbox.setButtonType(.switch)
        snapCheckbox.title = "Snap to other notes and screen edges when moving or resizing"
        target(snapCheckbox, #selector(snapChanged))
        let snapHint = hint("Hold ⌘ while dragging to place a note freely.")

        let grid = NSGridView(views: [
            [label("New note color:"), colorPopup],
            [label("Font:"), fontRow],
            [label("Text color:"), textColorWell],
            [label("Preview:"), preview],
            [label("New note size:"), sizeRow],
            [NSGridCell.emptyContentView, useRow],
            [NSGridCell.emptyContentView, useHint],
            [label("Arranging:"), snapCheckbox],
            [NSGridCell.emptyContentView, snapHint],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.row(at: 3).yPlacement = .center
        grid.row(at: 3).rowAlignment = .none
        grid.row(at: 2).rowAlignment = .none
        grid.row(at: 2).yPlacement = .center
        grid.row(at: 4).topPadding = 12
        grid.row(at: 6).topPadding = -4
        grid.row(at: 7).topPadding = 12
        grid.row(at: 8).topPadding = -4

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])

        let w = PrefsWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Desktop Notes Preferences"
        w.isReleasedWhenClosed = false
        w.contentView = container
        w.delegate = self
        w.setContentSize(container.fittingSize)
        w.center()
        window = w
    }

    private func target(_ control: NSControl, _ action: Selector) {
        control.target = self
        control.action = action
    }

    private func numberField(_ field: NSTextField, _ action: Selector, width: CGFloat) {
        let f = NumberFormatter()
        f.allowsFloats = false
        f.minimum = 1
        field.formatter = f
        field.alignment = .right
        target(field, action)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private func hint(_ s: String) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        t.textColor = .secondaryLabelColor
        t.preferredMaxLayoutWidth = 400
        return t
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = .firstBaseline
        s.spacing = 6
        return s
    }
}
