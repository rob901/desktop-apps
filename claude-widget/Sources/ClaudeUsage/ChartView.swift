import AppKit

/// A single-series line + area chart of a usage percentage over time (0–100, one axis).
/// Lines break where readings are missing; a lone reading is drawn as a dot.
/// Hovering shows a crosshair and the nearest reading.
final class ChartView: NSView {
    typealias Point = (date: Date, value: Double)

    var segments: [[Point]] = [] { didSet { changed() } }
    var range: ChartRange = .day { didSet { changed() } }
    var now = Date() { didSet { needsDisplay = true } }
    var emptyMessage = ""

    private var hoverX: CGFloat?

    private static let axisFont = NSFont.systemFont(ofSize: 9)
    private static let tipFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func changed() {
        needsDisplay = true
        let points = segments.flatMap { $0 }
        if let last = points.last, let peak = points.map(\.value).max() {
            setAccessibilityLabel("\(range.chartTitle). Now \(Int(last.value))%, peak \(Int(peak))%.")
        } else {
            setAccessibilityLabel("\(range.chartTitle). \(emptyMessage)")
        }
    }

    // MARK: Geometry

    private var plot: NSRect {
        NSRect(x: bounds.minX + 26, y: bounds.minY + 15, width: max(1, bounds.width - 32), height: max(1, bounds.height - 21))
    }

    private var start: Date { now.addingTimeInterval(-range.span) }

    private func x(_ d: Date) -> CGFloat {
        plot.minX + CGFloat(d.timeIntervalSince(start) / range.span) * plot.width
    }

    private func y(_ v: Double) -> CGFloat {
        plot.minY + CGFloat(v / 100) * plot.height
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawGrid()
        drawTimeAxis()
        if segments.isEmpty {
            drawEmpty()
            return
        }
        drawSeries()
        drawHover()
    }

    private func drawGrid() {
        for v in [0.0, 50.0, 100.0] {
            let yy = (y(v)).rounded(.down) + 0.5
            (v == 0 ? Ink.baseline : Ink.grid).setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: plot.minX, y: yy))
            p.line(to: NSPoint(x: plot.maxX, y: yy))
            p.lineWidth = 1
            p.stroke()
            let label = v == 100 ? "100%" : "\(Int(v))"
            let s = text(label, Self.axisFont, Ink.muted)
            let size = s.size()
            s.draw(at: NSPoint(x: plot.minX - 4 - size.width, y: yy - size.height / 2))
        }
    }

    private func drawTimeAxis() {
        let cal = Calendar.current
        var labels: [(x: CGFloat, text: String)] = []
        if range == .day {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("j")
            var d = cal.dateInterval(of: .hour, for: start)?.end ?? start
            while d <= now {
                if cal.component(.hour, from: d) % 6 == 0 { labels.append((x(d), f.string(from: d))) }
                d = d.addingTimeInterval(3600)
            }
        } else {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEE")
            var d = cal.startOfDay(for: start)
            while d < now {
                let next = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
                let a = max(x(d), plot.minX), b = min(x(next), plot.maxX)
                let s = text(f.string(from: d), Self.axisFont, Ink.muted)
                if b - a >= s.size().width + 2 { labels.append(((a + b) / 2, f.string(from: d))) }
                d = next
            }
        }
        for l in labels {
            let s = text(l.text, Self.axisFont, Ink.muted)
            let w = s.size().width
            let lx = min(max(l.x - w / 2, plot.minX - 2), plot.maxX - w)
            s.draw(at: NSPoint(x: lx, y: bounds.minY + 1))
        }
    }

    private func drawSeries() {
        let baseY = y(0)
        for seg in segments {
            let pts = seg.map { NSPoint(x: x($0.date), y: y($0.value)) }
            if pts.count == 1 {
                dot(at: pts[0])
                continue
            }
            let area = NSBezierPath()
            area.move(to: NSPoint(x: pts[0].x, y: baseY))
            pts.forEach { area.line(to: $0) }
            area.line(to: NSPoint(x: pts[pts.count - 1].x, y: baseY))
            area.close()
            Ink.series.withAlphaComponent(0.10).setFill()
            area.fill()

            let line = NSBezierPath()
            line.move(to: pts[0])
            pts.dropFirst().forEach { line.line(to: $0) }
            line.lineWidth = 2
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            Ink.series.setStroke()
            line.stroke()
        }
        if let last = segments.last?.last { dot(at: NSPoint(x: x(last.date), y: y(last.value))) }
    }

    /// An 8pt marker with a 2pt ring in the surface color.
    private func dot(at p: NSPoint) {
        Ink.surface.setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)).fill()
        Ink.series.setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
    }

    private func drawEmpty() {
        let s = text(emptyMessage, .systemFont(ofSize: 11), Ink.muted)
        let r = s.boundingRect(with: NSSize(width: plot.width - 16, height: plot.height), options: [.usesLineFragmentOrigin])
        s.draw(with: NSRect(x: plot.midX - r.width / 2, y: plot.midY - r.height / 2, width: r.width, height: r.height),
               options: [.usesLineFragmentOrigin])
    }

    // MARK: Hover

    private func drawHover() {
        guard let hoverX else { return }
        let all = segments.flatMap { $0 }
        guard let nearest = all.min(by: { abs(x($0.date) - hoverX) < abs(x($1.date) - hoverX) }) else { return }
        let p = NSPoint(x: x(nearest.date), y: y(nearest.value))

        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: p.x.rounded(.down) + 0.5, y: plot.minY))
        cross.line(to: NSPoint(x: p.x.rounded(.down) + 0.5, y: plot.maxY))
        cross.lineWidth = 1
        Ink.baseline.setStroke()
        cross.stroke()
        dot(at: p)

        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(range == .day ? "j:mm" : "EEE j:mm")
        let s = text("\(f.string(from: nearest.date))   \(Int(nearest.value.rounded()))%", Self.tipFont, Ink.primary)
        let size = s.size()
        var box = NSRect(x: p.x - size.width / 2 - 6, y: p.y + 10, width: size.width + 12, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = p.y - 10 - box.height }
        box.origin.x = min(max(box.minX, bounds.minX + 1), bounds.maxX - box.width - 1)
        let bg = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        NSColor.white.setFill()
        bg.fill()
        NSColor.black.withAlphaComponent(0.10).setStroke()
        bg.lineWidth = 1
        bg.stroke()
        s.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoverX = plot.insetBy(dx: -6, dy: -6).contains(p) ? p.x : nil
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverX = nil
        needsDisplay = true
    }

    private func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }
}
