import AppKit
import ServiceManagement

// Desktop Notes: sticky notes that live on the desktop layer.
//
// Each note is a borderless, non-activating panel placed one level above the
// desktop icons, so it is always behind every normal window. The `.stationary`
// collection behavior keeps it in place during Show Desktop / Mission Control,
// and `.canJoinAllSpaces` puts it on every Space.

// MARK: - Model

enum NoteColor: String, Codable, CaseIterable {
    case yellow, blue, green, pink, purple, gray

    var body: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.97, blue: 0.65, alpha: 1)
        case .blue:   return NSColor(srgbRed: 0.72, green: 0.87, blue: 1.00, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.74, green: 0.96, blue: 0.70, alpha: 1)
        case .pink:   return NSColor(srgbRed: 1.00, green: 0.78, blue: 0.84, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.86, green: 0.78, blue: 1.00, alpha: 1)
        case .gray:   return NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        }
    }

    var header: NSColor { body.blended(withFraction: 0.12, of: .black) ?? body }
    var title: String { rawValue.capitalized }
}

struct NoteData: Codable {
    var id: UUID
    var x: Double
    var top: Double          // y of the note's top edge (screen coordinates)
    var width: Double
    var height: Double       // expanded height, kept while collapsed
    var collapsed: Bool
    var color: NoteColor
    var rtf: Data
}

enum Store {
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    static func load() -> [NoteData] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([NoteData].self, from: data)
        } catch {
            // Never silently overwrite notes we failed to read: keep a copy.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("notes.unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("DesktopNotes: could not decode notes (\(error)); backed up to \(backup.path)")
            return []
        }
    }

    static func save(_ notes: [NoteData]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(notes).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("DesktopNotes: save failed: \(error)")
        }
    }
}

// MARK: - Window

final class NotePanel: NSPanel {
    weak var controller: NoteController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The app never becomes frontmost (that could end Show Desktop), so there is
    // no active menu bar. Handle the usual editing shortcuts here instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let send = { (sel: String) -> Bool in NSApp.sendAction(Selector(sel), to: nil, from: self) }

        if flags == .command {
            switch key {
            case "n": AppDelegate.shared.newNote(near: self); return true
            case "x": return send("cut:")
            case "c": return send("copy:")
            case "v": return send("paste:")
            case "a": return send("selectAll:")
            case "z": return send("undo:")
            case "b": controller?.toggleTrait(.boldFontMask); return true
            case "i": controller?.toggleTrait(.italicFontMask); return true
            case "u": return send("underline:")
            case "f": controller?.showFind(); return true
            case "=", "+": controller?.adjustFontSize(by: 1); return true
            case "-": controller?.adjustFontSize(by: -1); return true
            default: break
            }
        } else if flags == [.command, .shift] {
            switch key {
            case "z": return send("redo:")
            case "v": return send("pasteAsPlainText:")
            default: break
            }
        } else if flags == [.command, .option] && key == "v" {
            return send("pasteAsPlainText:")
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Top strip: drag to move, double-click to collapse/expand, right-click for options.
final class HeaderView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var onDoubleClick: (() -> Void)?
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
        } else {
            window?.makeKey()
            window?.performDrag(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}

/// Bottom-right resize corner (borderless windows have no edges to drag).
final class GripView: NSView {
    var minSize = NSSize(width: 130, height: 70)
    var onResized: (() -> Void)?

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
        let start = NSEvent.mouseLocation
        let original = window.frame
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = NSEvent.mouseLocation
            var f = original
            f.size.width = max(minSize.width, original.width + (p.x - start.x))
            f.size.height = max(minSize.height, original.height - (p.y - start.y))
            f.origin.y = original.maxY - f.height   // keep the top edge pinned
            window.setFrame(f, display: true)
            if e.type == .leftMouseUp { break }
        }
        onResized?()
    }
}

final class NoteContentView: NSView {
    weak var controller: NoteController?
    override func resizeSubviews(withOldSize oldSize: NSSize) { controller?.layout() }
}

// MARK: - Note

final class NoteController: NSObject, NSTextViewDelegate, NSWindowDelegate {
    static let headerHeight: CGFloat = 22
    static let defaultFont = NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14)

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

    init(data: NoteData) {
        id = data.id
        color = data.color
        collapsed = data.collapsed
        expandedHeight = max(CGFloat(data.height), 70)

        let height = collapsed ? Self.headerHeight : expandedHeight
        let rect = NSRect(x: data.x, y: data.top - Double(height), width: data.width, height: Double(height))
        panel = NotePanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init()

        configurePanel()
        configureHeader()
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
        panel.appearance = NSAppearance(named: .aqua)   // pastel notes always use dark text
        panel.delegate = self
    }

    private func configureHeader() {
        header.onDoubleClick = { [weak self] in self?.toggleCollapsed() }
        header.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }

        setUp(closeButton, symbol: "xmark", tip: "Delete Note", action: #selector(deleteNote))
        setUp(addButton, symbol: "plus", tip: "New Note (⌘N)", action: #selector(newNoteFromButton))
        setUp(collapseButton, symbol: "chevron.up", tip: "Collapse (double-click the bar)", action: #selector(toggleCollapsed))

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor.black.withAlphaComponent(0.7)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true

        for v in [closeButton, titleLabel, addButton, collapseButton] as [NSView] { header.addSubview(v) }
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
        tv.insertionPointColor = .black
        tv.typingAttributes = [.font: Self.defaultFont, .foregroundColor: NSColor.black]

        if !rtf.isEmpty, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attributed)
        }
        if tv.string.isEmpty {
            tv.typingAttributes = [.font: Self.defaultFont, .foregroundColor: NSColor.black]
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
        guard collapsed else { titleLabel.stringValue = ""; return }
        let first = textView.string.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        titleLabel.stringValue = first ?? ""
    }

    // MARK: Actions

    @objc private func newNoteFromButton() { AppDelegate.shared.newNote(near: panel) }

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
        let new = NSMenuItem(title: "New Note", action: #selector(newNoteFromButton), keyEquivalent: "")
        new.target = self
        menu.addItem(new)
        let collapse = NSMenuItem(title: collapsed ? "Expand" : "Collapse", action: #selector(toggleCollapsed), keyEquivalent: "")
        collapse.target = self
        menu.addItem(collapse)
        menu.addItem(.separator())
        for c in NoteColor.allCases {
            let item = NSMenuItem(title: c.title, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.rawValue
            item.state = c == color ? .on : .off
            item.image = swatch(c)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Note…", action: #selector(deleteNote), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    private func swatch(_ c: NoteColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            c.header.setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            return true
        }
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
            let f = attrs[.font] as? NSFont ?? Self.defaultFont
            attrs[.font] = fm.traits(of: f).contains(trait) ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
            textView.typingAttributes = attrs
            return
        }
        let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? Self.defaultFont
        let removing = fm.traits(of: first).contains(trait)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let f = value as? NSFont ?? Self.defaultFont
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
                let f = value as? NSFont ?? Self.defaultFont
                storage.addAttribute(.font, value: fm.convert(f, toSize: max(8, min(72, f.pointSize + delta))), range: sub)
            }
            storage.endEditing()
            textView.didChangeText()
        }
        var attrs = textView.typingAttributes
        let f = attrs[.font] as? NSFont ?? Self.defaultFont
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

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate!

    private(set) var notes: [NoteController] = []
    private var statusItem: NSStatusItem!
    private var saveTimer: Timer?
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        let saved = Store.load()
        if saved.isEmpty {
            newNote(near: nil)
        } else {
            for data in saved { add(NoteController(data: fitOnScreen(data))) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { saveNow() }

    // MARK: Notes

    @discardableResult
    private func add(_ note: NoteController) -> NoteController {
        notes.append(note)
        note.panel.orderFront(nil)
        return note
    }

    func newNote(near window: NSWindow?) {
        let size = NSSize(width: 240, height: 220)
        var x: CGFloat, top: CGFloat
        if let window {
            x = window.frame.minX + 28
            top = window.frame.maxY - 28
        } else {
            let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let n = CGFloat(notes.count % 8)
            x = vf.midX - size.width / 2 + n * 24
            top = vf.midY + size.height / 2 - n * 24
        }
        let data = NoteData(id: UUID(), x: x, top: top, width: size.width, height: size.height,
                            collapsed: false, color: .yellow, rtf: Data())
        add(NoteController(data: fitOnScreen(data))).focus()
        scheduleSave()
    }

    func remove(_ note: NoteController) {
        note.panel.orderOut(nil)
        notes.removeAll { $0 === note }
        saveNow()
    }

    /// Notes saved on a display that's no longer attached are moved back onto the main screen.
    private func fitOnScreen(_ data: NoteData) -> NoteData {
        var d = data
        let probe = NSRect(x: d.x, y: d.top - 22, width: d.width, height: 22)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(probe) }) { return d }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        d.x = vf.midX - d.width / 2
        d.top = vf.midY + d.height / 2
        return d
    }

    // MARK: Saving

    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        Store.save(notes.map { $0.snapshot() })
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Desktop Notes")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("New Note", #selector(menuNewNote)))
        menu.addItem(item("Collapse All", #selector(collapseAll)))
        menu.addItem(item("Expand All", #selector(expandAll)))
        menu.addItem(.separator())
        launchAtLoginItem = item("Open at Login", #selector(toggleLaunchAtLogin))
        menu.addItem(launchAtLoginItem)
        menu.addItem(item("Show Notes File in Finder", #selector(revealStore)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Desktop Notes", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func menuNewNote() { newNote(near: nil) }
    @objc private func collapseAll() { notes.forEach { $0.setCollapsed(true) } }
    @objc private func expandAll() { notes.forEach { $0.setCollapsed(false) } }
    @objc private func revealStore() { NSWorkspace.shared.activateFileViewerSelecting([Store.fileURL]) }
    @objc private func quit() { saveNow(); NSApp.terminate(nil) }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
