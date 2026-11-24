import AppKit

/// Magnetic alignment for moving and resizing notes, similar to the guides in
/// Keynote/Freeform: edges and sizes pull toward other notes, the screen edges,
/// and the default note size when they come within a few points. Hold ⌘ to bypass.
enum Snapper {
    static let threshold: CGFloat = 8

    struct Context {
        var frames: [NSRect]       // other notes as they currently appear
        var sizes: [NSSize]        // other notes' expanded sizes, plus the default size
        var screens: [NSRect]
    }

    static func context(excluding note: NoteController) -> Context {
        let others = AppDelegate.shared.notes.filter { $0 !== note }
        return Context(frames: others.map { $0.panel.frame },
                       sizes: others.map { $0.expandedSize } + [Prefs.size],
                       screens: NSScreen.screens.map { $0.visibleFrame })
    }

    static var bypassed: Bool { !Prefs.snapping || NSEvent.modifierFlags.contains(.command) }

    /// The candidate closest to `value`, if one is within the threshold.
    private static func nearest(_ value: CGFloat, _ candidates: [CGFloat]) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = threshold
        for c in candidates where abs(c - value) <= bestDistance {
            bestDistance = abs(c - value)
            best = c
        }
        return best
    }

    /// True if the ranges overlap or nearly touch.
    private static func near(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool {
        a0 <= b1 + threshold && b0 <= a1 + threshold
    }

    /// Snaps a proposed frame for a move. Returns the adjusted origin and which axes snapped.
    static func move(_ f: NSRect, in c: Context) -> (origin: NSPoint, snappedX: CGFloat?, snappedY: CGFloat?) {
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for o in c.frames {
            xs += [o.minX, o.maxX - f.width]                       // align left / right edges
            ys += [o.maxY - f.height, o.minY]                      // align top / bottom edges
            if near(f.minY, f.maxY, o.minY, o.maxY) {
                xs += [o.maxX, o.minX - f.width]                   // sit beside it
            }
            if near(f.minX, f.maxX, o.minX, o.maxX) {
                ys += [o.minY - f.height, o.maxY]                  // stack below / above it
            }
        }
        for s in c.screens {
            xs += [s.minX, s.maxX - f.width]
            ys += [s.minY, s.maxY - f.height]
        }
        let x = nearest(f.minX, xs), y = nearest(f.minY, ys)
        return (NSPoint(x: x ?? f.minX, y: y ?? f.minY), x, y)
    }

    /// Snaps a proposed size for a resize from the bottom-right corner (top-left stays fixed).
    static func resize(_ f: NSRect, in c: Context) -> (size: NSSize, snappedW: CGFloat?, snappedH: CGFloat?) {
        var ws = c.sizes.map(\.width), hs = c.sizes.map(\.height)
        for o in c.frames {
            ws.append(o.maxX - f.minX)                             // right edges line up
            hs.append(f.maxY - o.minY)                             // bottom edges line up
            if near(f.minY, f.maxY, o.minY, o.maxY) { ws.append(o.minX - f.minX) }   // touch its left edge
            if near(f.minX, f.maxX, o.minX, o.maxX) { hs.append(f.maxY - o.maxY) }   // touch its top edge
        }
        for s in c.screens {
            ws.append(s.maxX - f.minX)
            hs.append(f.maxY - s.minY)
        }
        ws = ws.filter { $0 >= minNoteSize.width }
        hs = hs.filter { $0 >= minNoteSize.height }
        let w = nearest(f.width, ws), h = nearest(f.height, hs)
        return (NSSize(width: w ?? f.width, height: h ?? f.height), w, h)
    }
}

/// Plays the trackpad's "alignment" tick each time a snap engages, like the system does.
struct SnapFeedback {
    private var last: (CGFloat?, CGFloat?) = (nil, nil)

    mutating func update(_ a: CGFloat?, _ b: CGFloat?) {
        let engagedNew = (a != nil && a != last.0) || (b != nil && b != last.1)
        if engagedNew {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        last = (a, b)
    }
}
