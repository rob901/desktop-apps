import AppKit
import ServiceManagement

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
        let size = Prefs.size
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
                            collapsed: false, color: Prefs.color, rtf: Data())
        add(NoteController(data: fitOnScreen(data))).focus()
        scheduleSave()
        PreferencesController.shared.notesChanged()
    }

    func remove(_ note: NoteController) {
        note.panel.orderOut(nil)
        notes.removeAll { $0 === note }
        saveNow()
        PreferencesController.shared.notesChanged()
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
        menu.addItem(item("Preferences…", #selector(openPreferences)))
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
    @objc private func openPreferences() { PreferencesController.shared.show() }
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
