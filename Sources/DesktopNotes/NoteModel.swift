import AppKit
import DesktopKit

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

    var theme: WidgetTheme { WidgetTheme(body: body) }
    var title: String { rawValue.capitalized }
    func swatch() -> NSImage { theme.swatch() }
}

/// One saved note. The JSON shape matches the original Desktop Stickies, so existing
/// notes.json files load unchanged.
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

extension NoteData {
    init(id: UUID, frame: WidgetFrame, color: NoteColor, rtf: Data) {
        self.init(id: id, x: frame.x, top: frame.top, width: frame.width, height: frame.height,
                  collapsed: frame.collapsed, color: color, rtf: rtf)
    }

    var frame: WidgetFrame {
        get { WidgetFrame(x: x, top: top, width: width, height: height, collapsed: collapsed) }
        set { x = newValue.x; top = newValue.top; width = newValue.width; height = newValue.height; collapsed = newValue.collapsed }
    }
}

/// Smallest size a note can be resized to.
let minNoteSize = NSSize(width: 130, height: 70)

/// User preferences for new notes, stored in UserDefaults.
/// (Snapping is a framework setting: `DesktopSettings.snapping`.)
enum NotePrefs {
    private static let d = UserDefaults.standard

    static var color: NoteColor {
        get { d.string(forKey: "defaultColor").flatMap(NoteColor.init(rawValue:)) ?? .yellow }
        set { d.set(newValue.rawValue, forKey: "defaultColor") }
    }

    static var fontFamily: String {
        get { d.string(forKey: "fontFamily") ?? "Helvetica" }
        set { d.set(newValue, forKey: "fontFamily") }
    }

    static var fontSize: CGFloat {
        get { let v = d.double(forKey: "fontSize"); return v > 0 ? CGFloat(v) : 14 }
        set { d.set(Double(newValue), forKey: "fontSize") }
    }

    static var textColor: NSColor {
        get {
            if let data = d.data(forKey: "textColor"),
               let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) { return c }
            return .black
        }
        set { d.set(try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true), forKey: "textColor") }
    }

    static var size: NSSize {
        get {
            let w = d.double(forKey: "width"), h = d.double(forKey: "height")
            return NSSize(width: w >= minNoteSize.width ? w : 240, height: h >= minNoteSize.height ? h : 220)
        }
        set {
            d.set(Double(max(minNoteSize.width, newValue.width.rounded())), forKey: "width")
            d.set(Double(max(minNoteSize.height, newValue.height.rounded())), forKey: "height")
        }
    }

    static var font: NSFont {
        NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: fontSize)
            ?? NSFont(name: "Helvetica", size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor]
    }
}
