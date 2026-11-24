import AppKit

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

    func swatch() -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            self.header.setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            return true
        }
    }
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

/// Smallest size a note can be resized to.
let minNoteSize = NSSize(width: 130, height: 70)

/// User preferences for new notes, stored in UserDefaults.
enum Prefs {
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

    static var snapping: Bool {
        get { d.object(forKey: "snapping") as? Bool ?? true }
        set { d.set(newValue, forKey: "snapping") }
    }

    static var font: NSFont {
        NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: fontSize)
            ?? NSFont(name: "Helvetica", size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor]
    }
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

/// The app is never frontmost while you use a note, so there is no active menu bar
/// to provide the standard editing shortcuts. Windows call this instead.
func performStandardEditShortcut(_ event: NSEvent, from sender: Any?) -> Bool {
    guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    var action: String?
    if flags == .command {
        action = ["x": "cut:", "c": "copy:", "v": "paste:", "a": "selectAll:", "z": "undo:"][key]
    } else if flags == [.command, .shift], key == "z" {
        action = "redo:"
    }
    guard let action else { return false }
    return NSApp.sendAction(Selector(action), to: nil, from: sender)
}
