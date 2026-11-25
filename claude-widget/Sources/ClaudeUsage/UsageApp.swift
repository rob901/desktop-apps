import AppKit
import DesktopKit

/// Claude Usage: one desktop widget showing plan usage. No menu-bar icon; everything
/// (Day/Week, Preferences, Open at Login, Quit) is in the widget's right-click menu.
final class UsageApp: NSObject, DesktopWidgetApp, WidgetWindowDelegate {
    static let shared = UsageApp()

    let info = DesktopAppInfo(name: "Claude Usage", statusItem: nil)
    let preferencesPane: PreferencesPane? = UsagePreferencesPane()
    var dataFileURL: URL? { source.url }

    let source = UsageSource()
    private let store = JSONStore<WidgetState>(folder: "ClaudeUsage", file: "widget.json")
    private lazy var saver = SaveScheduler { [weak self] in self?.save() }
    private lazy var ticker = PeriodicTask(interval: 30) { [weak self] in self?.tick() }
    private var window: WidgetWindow!
    private let view = UsageView()
    private var range: ChartRange = .day

    static let minSize = NSSize(width: 230, height: 180)

    // MARK: Lifecycle

    func didLaunch() {
        let state = store.load()
        range = state?.range ?? .day
        let frame = state?.frame.fittedOnScreen() ?? defaultFrame()
        window = WidgetWindow(frame: frame, theme: Ink.theme, options: WidgetWindowOptions(minSize: Self.minSize))
        window.title = "Claude usage"
        window.contentView = view
        window.delegate = self
        view.onRangeChange = { [weak self] in self?.setRange($0) }
        window.show()
        ticker.start()
        if state == nil { saver.schedule() }
        writeSnapshotIfRequested()
    }

    /// Development aid: `ClaudeUsage --snapshot <file.png> [day|week]` renders the widget to a PNG and quits.
    private func writeSnapshotIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        if i + 2 < args.count, let r = ChartRange(rawValue: args[i + 2]) { range = r; refreshDisplay() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let content = self.window.panel.contentView,
                  let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
        }
    }

    func willTerminate() { saver.flush() }

    /// Top-right corner of the main screen.
    private func defaultFrame() -> WidgetFrame {
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let w = 290.0, h = 210.0
        return WidgetFrame(x: vf.maxX - w - 24, top: vf.maxY - 24, width: w, height: h)
    }

    private func save() {
        guard let window else { return }
        store.save(WidgetState(frame: window.frame, range: range))
    }

    // MARK: Updating

    private func tick() {
        source.reloadIfChanged()
        refreshDisplay()
    }

    /// Redraws with current data and settings.
    func refreshDisplay() {
        view.update(source: source, range: range, now: Date())
        window?.refreshTitle()
    }

    private func setRange(_ r: ChartRange) {
        range = r
        refreshDisplay()
        saver.schedule()
    }

    // MARK: WidgetWindowDelegate

    func widgetWindowDidChangeFrame(_ window: WidgetWindow) { saver.schedule() }

    func widgetWindowCollapsedTitle(_ window: WidgetWindow) -> String? {
        guard let s = source.latest else { return nil }
        let pct = { (v: Double?) in v.map { "\(Int($0.rounded()))%" } ?? "—" }
        return "Claude · session \(pct(s.session)) · week \(pct(s.week))"
    }

    func widgetWindowMenu(_ window: WidgetWindow) -> NSMenu? {
        let menu = NSMenu()
        for r in ChartRange.allCases {
            let i = NSMenuItem(title: r == .day ? "Day (session usage)" : "Week (weekly usage)",
                               action: #selector(pickRange(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = r.rawValue
            i.state = r == range ? .on : .off
            menu.addItem(i)
        }
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        let collapse = NSMenuItem(title: window.isCollapsed ? "Expand" : "Collapse", action: #selector(toggleCollapsed), keyEquivalent: "")
        collapse.target = self
        menu.addItem(collapse)
        menu.addItem(.separator())
        DesktopApp.host.standardMenuItems(revealDataTitle: "Show Usage File in Finder").forEach(menu.addItem)
        return menu
    }

    func widgetWindow(_ window: WidgetWindow, performKeyEquivalent event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "r": refreshNow(); return true
        case "1": setRange(.day); return true
        case "2": setRange(.week); return true
        case ",": DesktopApp.host.openPreferences(); return true
        default: return false
        }
    }

    // MARK: Actions

    @objc private func pickRange(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let r = ChartRange(rawValue: raw) { setRange(r) }
    }

    @objc private func refreshNow() { ticker.fire() }
    @objc private func toggleCollapsed() { window.toggleCollapsed() }
}
