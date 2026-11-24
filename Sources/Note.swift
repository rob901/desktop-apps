import AppKit

// Each note is a borderless, non-activating panel placed one level above the
// desktop icons, so it is always behind every normal window. The `.stationary`
// collection behavior keeps it in place during Show Desktop / Mission Control,
// and `.canJoinAllSpaces` puts it on every Space. Because the panel never
// activates the app, clicking a note doesn't end Show Desktop.

// MARK: - Window

final class NotePanel: NSPanel {
    weak var controller: NoteController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let send = { (sel: String) -> Bool in NSApp.sendAction(Selector(sel), to: nil, from: self) }

        if flags == .command {
            switch key {
            case "n": AppDelegate.shared.newNote(near: self); return true
            case "b": controller?.toggleTrait(.boldFontMask); return true
            case "i": controller?.toggleTrait(.italicFontMask); return true
            case "u": return send("underline:")
            case "f": controller?.showFind(); return true
            case "=", "+": controller?.adjustFontSize(by: 1); return true
            case "-": controller?.adjustFontSize(by: -1); return true
            case ",": PreferencesController.shared.show(); return true
            default: break
            }
        } else if (flags == [.command, .shift] || flags == [.command, .option]) && key == "v" {
            return send("pasteAsPlainText:")
        }
        if performStandardEditShortcut(event, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Runs a mouse-drag loop until the button is released, reporting the distance
/// moved since `mouseDown` (in screen points, y up).
private func trackDrag(from mouseDown: NSEvent, in window: NSWindow, _ step: (_ delta: NSPoint) -> Void) {
    // Use each event's own global position (not the live cursor), so the deltas
    // are exact even if events queue up.
    func location(_ e: NSEvent) -> CGPoint { e.cgEvent?.location ?? .zero }   // top-left origin
    let start = location(mouseDown)
    var moved = false
    while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
        let p = location(e)
        if e.type == .leftMouseDragged { moved = true }
        // Apply the release position too: the last drag event can be coalesced into the mouse-up.
        if moved { step(NSPoint(x: p.x - start.x, y: start.y - p.y)) }
        if e.type == .leftMouseUp { break }
    }
}

/// Top strip: drag to move, double-click to collapse/expand, right-click for options.
final class HeaderView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var onDoubleClick: (() -> Void)?
    var onDrag: ((_ delta: NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        guard let window else { return }
        window.makeKey()
        trackDrag(from: event, in: window) { onDrag?($0) }
        onDragEnded?()
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}

/// Bottom-right resize corner (borderless windows have no edges to drag).
final class GripView: NSView {
    var onDrag: ((_ delta: NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setStroke()
        let path = NSBezierPath()
        for inset in stride(from: CGFloat(3), through: 9, by: 3) {
            path.move(to: NSPoint(x: bounds.maxX - inset - 1, y: 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: inset + 1))
        }
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        trackDrag(from: event, in: window) { onDrag?($0) }
        onDragEnded?()
    }
}

final class NoteContentView: NSView {
    weak var controller: NoteController?
    override func resizeSubviews(withOldSize oldSize: NSSize) { controller?.layout() }
}

// MARK: - Note

final class NoteController: NSObject, NSTextViewDelegate, NSWindowDelegate {
    static let headerHeight: CGFloat = 22

    let id: UUID
    let panel: NotePanel
    private let content = NoteContentView()
    private let header = HeaderView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let addButton = NSButton()
    private let collapseButton = NSButton()
    private let scroll: NSScrollView
    let textView: NSTextView
    private let grip = GripView()

    private(set) var collapsed: Bool
    private var expandedHeight: CGFloat
    var color: NoteColor { didSet { applyColor() } }

    /// The note's size when expanded, even if it's collapsed right now.
    var expandedSize: NSSize {
        NSSize(width: panel.frame.width, height: collapsed ? expandedHeight : panel.frame.height)
    }

    /// First non-empty line of the note: what the bar shows when collapsed.
    var firstLine: String? {
        textView.string.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    init(data: NoteData) {
        id = data.id
        color = data.color
        collapsed = data.collapsed
        expandedHeight = max(CGFloat(data.height), minNoteSize.height)

        let height = collapsed ? Self.headerHeight : expandedHeight
        let rect = NSRect(x: data.x, y: data.top - Double(height), width: data.width, height: Double(height))
        panel = NotePanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init()

        configurePanel()
        configureHeader()
        configureGrip()
        configureText(rtf: data.rtf)
        content.controller = self
        content.addSubview(scroll)
        content.addSubview(grip)
        content.addSubview(header)
        panel.contentView = content
        applyColor()
        applyCollapsedState()
        layout()
    }

    private func configurePanel() {
        panel.controller = self
        panel.isFloatingPanel = false
        // One level above the desktop icons: always below every normal window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = true
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .aqua)   // pastel notes always use dark UI
        panel.delegate = self
    }

    private func configureHeader() {
        header.onDoubleClick = { [weak self] in self?.toggleCollapsed() }
        header.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }

        var startOrigin = NSPoint.zero
        var feedback = SnapFeedback()
        var context: Snapper.Context?
        header.onDrag = { [weak self] delta in
            guard let self else { return }
            if context == nil {
                startOrigin = self.panel.frame.origin
                context = Snapper.context(excluding: self)
            }
            var f = self.panel.frame
            f.origin = NSPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y)
            if !Snapper.bypassed, let context {
                let snap = Snapper.move(f, in: context)
                f.origin = snap.origin
                feedback.update(snap.snappedX, snap.snappedY)
            } else {
                feedback.update(nil, nil)
            }
            self.panel.setFrameOrigin(f.origin)
        }
        header.onDragEnded = {
            context = nil
            feedback = SnapFeedback()
        }

        setUp(closeButton, symbol: "xmark", tip: "Delete Note", action: #selector(deleteNote))
        setUp(addButton, symbol: "plus", tip: "New Note (⌘N)", action: #selector(newNoteFromButton))
        setUp(collapseButton, symbol: "chevron.up", tip: "Collapse (double-click the bar)", action: #selector(toggleCollapsed))

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor.black.withAlphaComponent(0.7)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true

        for v in [closeButton, titleLabel, addButton, collapseButton] as [NSView] { header.addSubview(v) }
    }

    private func configureGrip() {
        var startFrame = NSRect.zero
        var feedback = SnapFeedback()
        var context: Snapper.Context?
        grip.onDrag = { [weak self] delta in
            guard let self else { return }
            if context == nil {
                startFrame = self.panel.frame
                context = Snapper.context(excluding: self)
            }
            var f = startFrame
            f.size.width = max(minNoteSize.width, startFrame.width + delta.x)
            f.size.height = max(minNoteSize.height, startFrame.height - delta.y)
            if !Snapper.bypassed, let context {
                let snap = Snapper.resize(f, in: context)
                f.size = snap.size
                feedback.update(snap.snappedW, snap.snappedH)
            } else {
                feedback.update(nil, nil)
            }
            f.origin.y = startFrame.maxY - f.height   // keep the top edge pinned
            self.panel.setFrame(f, display: true)
        }
        grip.onDragEnded = {
            context = nil
            feedback = SnapFeedback()
            AppDelegate.shared.scheduleSave()
        }
    }

    private func setUp(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = NSColor.black.withAlphaComponent(0.5)
        b.toolTip = tip
        b.target = self
        b.action = action
    }

    private func configureText(rtf: Data) {
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let tv = textView
        tv.delegate = self
        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.insertionPointColor = Prefs.textColor
        tv.typingAttributes = Prefs.typingAttributes

        if !rtf.isEmpty, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attributed)
        }
        if tv.string.isEmpty {
            tv.typingAttributes = Prefs.typingAttributes
        }
    }

    func layout() {
        let b = content.bounds
        let h = Self.headerHeight
        header.frame = NSRect(x: 0, y: b.height - h, width: b.width, height: h)
        scroll.frame = NSRect(x: 0, y: 0, width: b.width, height: max(0, b.height - h))
        grip.frame = NSRect(x: b.width - 14, y: 0, width: 14, height: 14)

        let s: CGFloat = 18, y = (h - s) / 2
        closeButton.frame = NSRect(x: 3, y: y, width: s, height: s)
        collapseButton.frame = NSRect(x: b.width - s - 3, y: y, width: s, height: s)
        addButton.frame = NSRect(x: b.width - 2 * s - 5, y: y, width: s, height: s)
        titleLabel.frame = NSRect(x: s + 6, y: (h - 15) / 2, width: max(0, b.width - 4 * s - 14), height: 15)
    }

    private func applyColor() {
        content.wantsLayer = true
        content.layer?.backgroundColor = color.body.cgColor
        content.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        content.layer?.borderWidth = 0.5
        header.fill = color.header
        panel.backgroundColor = color.body
    }

    // MARK: Collapse

    @objc func toggleCollapsed() { setCollapsed(!collapsed) }

    func setCollapsed(_ value: Bool) {
        guard value != collapsed else { return }
        var f = panel.frame
        let top = f.maxY
        if value { expandedHeight = f.height }
        collapsed = value
        f.size.height = value ? Self.headerHeight : expandedHeight
        f.origin.y = top - f.height
        panel.setFrame(f, display: true, animate: false)
        applyCollapsedState()
        AppDelegate.shared.scheduleSave()
    }

    private func applyCollapsedState() {
        scroll.isHidden = collapsed
        grip.isHidden = collapsed
        collapseButton.image = NSImage(systemSymbolName: collapsed ? "chevron.down" : "chevron.up",
                                       accessibilityDescription: collapsed ? "Expand" : "Collapse")
        collapseButton.toolTip = collapsed ? "Expand (double-click the bar)" : "Collapse (double-click the bar)"
        updateTitle()
        if collapsed, panel.firstResponder === textView { panel.makeFirstResponder(nil) }
    }

    private func updateTitle() {
        // Like Stickies: a collapsed note shows its first line in the bar.
        titleLabel.stringValue = collapsed ? (firstLine ?? "") : ""
    }

    // MARK: Actions

    @objc private func newNoteFromButton() { AppDelegate.shared.newNote(near: panel) }

    @objc private func useSizeAsDefault() {
        Prefs.size = expandedSize
        PreferencesController.shared.notesChanged()
    }

    @objc private func openPreferences() { PreferencesController.shared.show() }

    @objc func deleteNote() {
        if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppDelegate.shared.remove(self)
            return
        }
        if collapsed { setCollapsed(false) }
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "Its contents will be lost."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            AppDelegate.shared.remove(self)
        }
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = NoteColor(rawValue: raw) else { return }
        color = c
        AppDelegate.shared.scheduleSave()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add("New Note", #selector(newNoteFromButton))
        add(collapsed ? "Expand" : "Collapse", #selector(toggleCollapsed))
        menu.addItem(.separator())
        for c in NoteColor.allCases {
            let item = NSMenuItem(title: c.title, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.rawValue
            item.state = c == color ? .on : .off
            item.image = c.swatch()
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let s = expandedSize
        add("Use This Size (\(Int(s.width))×\(Int(s.height))) for New Notes", #selector(useSizeAsDefault))
        add("Preferences…", #selector(openPreferences))
        menu.addItem(.separator())
        add("Delete Note…", #selector(deleteNote))
        return menu
    }

    func focus() {
        panel.orderFront(nil)
        panel.makeKey()
        if !collapsed { panel.makeFirstResponder(textView) }
    }

    // MARK: Text formatting

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let storage = textView.textStorage else { return }
        let fm = NSFontManager.shared
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let f = attrs[.font] as? NSFont ?? Prefs.font
            attrs[.font] = fm.traits(of: f).contains(trait) ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
            textView.typingAttributes = attrs
            return
        }
        let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? Prefs.font
        let removing = fm.traits(of: first).contains(trait)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let f = value as? NSFont ?? Prefs.font
            storage.addAttribute(.font, value: removing ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait), range: sub)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func adjustFontSize(by delta: CGFloat) {
        guard let storage = textView.textStorage else { return }
        var range = textView.selectedRange()
        if range.length == 0 { range = NSRange(location: 0, length: storage.length) }   // whole note
        let fm = NSFontManager.shared
        if range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let f = value as? NSFont ?? Prefs.font
                storage.addAttribute(.font, value: fm.convert(f, toSize: max(8, min(72, f.pointSize + delta))), range: sub)
            }
            storage.endEditing()
            textView.didChangeText()
        }
        var attrs = textView.typingAttributes
        let f = attrs[.font] as? NSFont ?? Prefs.font
        attrs[.font] = fm.convert(f, toSize: max(8, min(72, f.pointSize + delta)))
        textView.typingAttributes = attrs
    }

    func showFind() {
        if collapsed { setCollapsed(false) }
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }

    // MARK: Delegates

    func textDidChange(_ notification: Notification) {
        if collapsed { updateTitle() }
        AppDelegate.shared.scheduleSave()
    }

    func windowDidMove(_ notification: Notification) { AppDelegate.shared.scheduleSave() }
    func windowDidResize(_ notification: Notification) { AppDelegate.shared.scheduleSave() }

    // MARK: Persistence

    func snapshot() -> NoteData {
        let f = panel.frame
        let storage = textView.textStorage ?? NSTextStorage()
        let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:]) ?? Data()
        return NoteData(id: id, x: f.minX, top: f.maxY, width: f.width,
                        height: collapsed ? expandedHeight : f.height,
                        collapsed: collapsed, color: color, rtf: rtf)
    }
}
