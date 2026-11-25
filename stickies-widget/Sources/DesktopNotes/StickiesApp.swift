import AppKit
import DesktopKit

final class StickiesApp: NSObject, DesktopWidgetApp {
    static let shared = StickiesApp()

    let info = DesktopAppInfo(
        name: "Desktop Notes",
        statusItem: StatusItemConfig(symbolName: "note.text", revealDataTitle: "Show Notes File in Finder")
    )
    let preferencesPane: PreferencesPane? = NotePreferencesPane()
    var dataFileURL: URL? { store.fileURL }

    private let store = JSONStore<[NoteData]>(folder: "DesktopNotes", file: "notes.json")
    private(set) lazy var saver = SaveScheduler { [weak self] in self?.saveNow() }
    private(set) var notes: [NoteController] = []

    // MARK: Lifecycle

    func didLaunch() {
        let saved = store.load() ?? []
        if saved.isEmpty {
            newNote(near: nil)
        } else {
            for var data in saved {
                data.frame = data.frame.fittedOnScreen()
                add(NoteController(data: data))
            }
        }
    }

    func willTerminate() { saver.flush() }

    func statusMenuItems() -> [NSMenuItem] {
        [item("New Note", #selector(menuNewNote)),
         item("Collapse All", #selector(collapseAll)),
         item("Expand All", #selector(expandAll))]
    }

    // MARK: Notes

    @discardableResult
    private func add(_ note: NoteController) -> NoteController {
        notes.append(note)
        note.window.show()
        return note
    }

    func newNote(near window: NSWindow?) {
        let size = NotePrefs.size
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
        let frame = WidgetFrame(x: x, top: top, width: size.width, height: size.height).fittedOnScreen()
        let data = NoteData(id: UUID(), frame: frame, color: NotePrefs.color, rtf: Data())
        add(NoteController(data: data)).focus()
        saver.schedule()
        DesktopApp.host.refreshPreferences()
    }

    func remove(_ note: NoteController) {
        note.window.close()
        notes.removeAll { $0 === note }
        saver.flush()
        DesktopApp.host.refreshPreferences()
    }

    private func saveNow() {
        store.save(notes.map { $0.snapshot() })
    }

    // MARK: Menu bar

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func menuNewNote() { newNote(near: nil) }
    @objc private func collapseAll() { notes.forEach { $0.window.setCollapsed(true) } }
    @objc private func expandAll() { notes.forEach { $0.window.setCollapsed(false) } }
}
