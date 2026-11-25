import AppKit

/// The widget's content: two stat tiles with meters (session, week), the Day/Week
/// switch, the chart, and a "last updated" line.
final class UsageView: NSView {
    let chart = ChartView()
    private let rangeControl = NSSegmentedControl(labels: ChartRange.allCases.map(\.label),
                                                  trackingMode: .selectOne, target: nil, action: nil)
    var onRangeChange: ((ChartRange) -> Void)?

    private var session: Double?
    private var week: Double?
    private var updated: Date?
    private var range: ChartRange = .day
    private var now = Date()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        rangeControl.controlSize = .mini
        rangeControl.font = .systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        rangeControl.target = self
        rangeControl.action = #selector(rangeClicked)
        rangeControl.selectedSegment = 0
        addSubview(rangeControl)
        addSubview(chart)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(source: UsageSource, range: ChartRange, now: Date) {
        self.range = range
        self.now = now
        session = source.latest?.session
        week = source.latest?.week
        updated = source.latest?.date
        rangeControl.selectedSegment = ChartRange.allCases.firstIndex(of: range) ?? 0
        chart.now = now
        chart.range = range
        chart.emptyMessage = source.problem
            ?? (range == .day ? "No readings in the last 24 hours." : "No readings in the last 7 days.")
        chart.segments = source.segments(for: range, now: now)
        needsDisplay = true
    }

    @objc private func rangeClicked() {
        onRangeChange?(ChartRange.allCases[max(0, rangeControl.selectedSegment)])
    }

    // MARK: Layout

    private let pad: CGFloat = 10
    private var tilesTop: CGFloat { 8 }
    private var controlsTop: CGFloat { 62 }
    private var footerHeight: CGFloat { 16 }

    override func layout() {
        super.layout()
        rangeControl.sizeToFit()
        let c = rangeControl.frame.size
        rangeControl.frame = NSRect(x: bounds.width - pad - c.width, y: controlsTop - 1, width: c.width, height: c.height)
        let chartTop = controlsTop + 22
        chart.frame = NSRect(x: pad - 4, y: chartTop, width: bounds.width - 2 * pad + 4,
                             height: max(0, bounds.height - chartTop - footerHeight - 4))
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) { needsLayout = true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let tileW = (bounds.width - 2 * pad - 12) / 2
        drawTile("Session", session, in: NSRect(x: pad, y: tilesTop, width: tileW, height: 46))
        drawTile("This week", week, in: NSRect(x: pad + tileW + 12, y: tilesTop, width: tileW, height: 46))

        let title = text(range.chartTitle, .systemFont(ofSize: 10, weight: .medium), Ink.secondary)
        title.draw(with: NSRect(x: pad, y: controlsTop + 2, width: rangeControl.frame.minX - pad - 6, height: 14),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        if let footer = footerText() {
            text(footer, .systemFont(ofSize: 9), Ink.muted)
                .draw(with: NSRect(x: pad, y: bounds.height - footerHeight, width: bounds.width - 2 * pad, height: 12),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    /// Label, big value, and a 4pt meter whose color carries severity (with an icon, never color alone).
    private func drawTile(_ label: String, _ value: Double?, in r: NSRect) {
        text(label, .systemFont(ofSize: 10, weight: .medium), Ink.secondary).draw(at: NSPoint(x: r.minX, y: r.minY))

        let valueString = text(value.map { "\(Int($0.rounded()))%" } ?? "—", .systemFont(ofSize: 20, weight: .semibold), Ink.primary)
        valueString.draw(at: NSPoint(x: r.minX, y: r.minY + 12))

        let level = value.map(Ink.level(for:)) ?? .normal
        let color = Ink.color(for: level)
        if level != .normal, let icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                accessibilityDescription: level == .critical ? "Near limit" : "High usage") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                .applying(.init(paletteColors: [color]))
            let img = icon.withSymbolConfiguration(config) ?? icon
            let w = valueString.size().width
            img.draw(in: NSRect(x: r.minX + w + 4, y: r.minY + 19, width: 13, height: 12), from: .zero,
                     operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        let track = NSRect(x: r.minX, y: r.maxY - 4, width: r.width, height: 4)
        (value == nil ? Ink.grid : color.withAlphaComponent(0.2)).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        if let value, value > 0 {
            color.setFill()
            let fill = NSRect(x: track.minX, y: track.minY, width: max(4, track.width * CGFloat(value / 100)), height: 4)
            NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func footerText() -> String? {
        guard let updated else { return nil }
        let age = now.timeIntervalSince(updated)
        let ago: String
        switch age {
        case ..<60: ago = "just now"
        case ..<3600: ago = "\(Int(age / 60)) min ago"
        case ..<86400: ago = "\(Int(age / 3600)) h ago"
        default: ago = "\(Int(age / 86400)) d ago"
        }
        return age > 30 * 60 ? "Last reading \(ago) · open the Claude app to update" : "Updated \(ago)"
    }

    private func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }
}
