import AppKit
import DesktopKit

/// One sticky note: a framework `WidgetWindow` whose content is a rich-text view.
final class NoteController: NSObject, NSTextViewDelegate, WidgetWindowDelegate {
    let id: UUID
    let window: WidgetWindow
    let textView: NSTextView
    private let scroll: NSScrollView

    var color: NoteColor { didSet { window.theme = color.theme } }
    var panel: DesktopPanel { window.panel }
    var collapsed: Bool { window.isCollapsed }
    var expandedSize: NSSize { window.expandedSize }

    /// First non-empty line of the note: what the bar shows when collapsed.
    var firstLine: String? {
        textView.string.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    init(data: NoteData) {
        id = data.id
        color = data.color
        window = WidgetWindow(frame: data.frame, theme: data.color.theme,
                              options: WidgetWindowOptions(minSize: minNoteSize))
        scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init()

        configureText(rtf: data.rtf)
        window.contentView = scroll
        window.leadingButtons = [
            WidgetWindow.makeHeaderButton(symbol: "xmark", toolTip: "Delete Note", target: self, action: #selector(deleteNote)),
        ]
        window.trailingButtons = [
            WidgetWindow.makeHeaderButton(symbol: "plus", toolTip: "New Note (⌘N)", target: self, action: #selector(newNoteFromButton)),
        ]
        window.delegate = self
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
        tv.insertionPointColor = NotePrefs.textColor
        tv.typingAttributes = NotePrefs.typingAttributes

        if !rtf.isEmpty, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attributed)
        }
        if tv.string.isEmpty {
            tv.typingAttributes = NotePrefs.typingAttributes
        }
    }

    func focus() { window.focus(textView) }

    // MARK: Actions

    @objc func toggleCollapsed() { window.toggleCollapsed() }

    @objc private func newNoteFromButton() { StickiesApp.shared.newNote(near: panel) }

    @objc private func useSizeAsDefault() {
        NotePrefs.size = expandedSize
        DesktopApp.host.refreshPreferences()
    }

    @objc private func openPreferences() { DesktopApp.host.openPreferences() }

    @objc func deleteNote() {
        if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            StickiesApp.shared.remove(self)
            return
        }
        if collapsed { window.setCollapsed(false) }
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "Its contents will be lost."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            StickiesApp.shared.remove(self)
        }
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = NoteColor(rawValue: raw) else { return }
        color = c
        StickiesApp.shared.saver.schedule()
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

    // MARK: WidgetWindowDelegate

    func widgetWindowDidChangeFrame(_ window: WidgetWindow) { StickiesApp.shared.saver.schedule() }
    func widgetWindowCollapsedTitle(_ window: WidgetWindow) -> String? { firstLine }   // like Stickies
    func widgetWindowMenu(_ window: WidgetWindow) -> NSMenu? { makeMenu() }
    func widgetWindowSnapSizes(_ window: WidgetWindow) -> [NSSize] { [NotePrefs.size] }

    func widgetWindow(_ window: WidgetWindow, performKeyEquivalent event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let send = { (sel: String) -> Bool in NSApp.sendAction(Selector(sel), to: nil, from: self.panel) }

        if flags == .command {
            switch key {
            case "n": StickiesApp.shared.newNote(near: panel); return true
            case "b": toggleTrait(.boldFontMask); return true
            case "i": toggleTrait(.italicFontMask); return true
            case "u": return send("underline:")
            case "f": showFind(); return true
            case "=", "+": adjustFontSize(by: 1); return true
            case "-": adjustFontSize(by: -1); return true
            case ",": DesktopApp.host.openPreferences(); return true
            default: break
            }
        } else if (flags == [.command, .shift] || flags == [.command, .option]) && key == "v" {
            return send("pasteAsPlainText:")
        }
        return false
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        if collapsed { window.refreshTitle() }
        StickiesApp.shared.saver.schedule()
    }

    // MARK: Persistence

    func snapshot() -> NoteData {
        let storage = textView.textStorage ?? NSTextStorage()
        let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:]) ?? Data()
        return NoteData(id: id, frame: window.frame, color: color, rtf: rtf)
    }
}
