import AppKit
import DesktopKit

/// Claude Usage settings, stored in this app's UserDefaults.
enum UsageSettings {
    private static let d = UserDefaults.standard

    /// Meters turn amber at this percentage.
    static var warningLevel: Int {
        get { let v = d.integer(forKey: "warningLevel"); return v > 0 ? v : 70 }
        set { d.set(min(99, max(1, newValue)), forKey: "warningLevel") }
    }

    /// Meters turn red at this percentage.
    static var criticalLevel: Int {
        get { let v = d.integer(forKey: "criticalLevel"); return v > 0 ? v : 90 }
        set { d.set(min(100, max(1, newValue)), forKey: "criticalLevel") }
    }
}

/// Where the widget is and which view it shows; saved between launches.
struct WidgetState: Codable {
    var frame: WidgetFrame
    var range: ChartRange
}

/// Colors and type. Chart colors follow a validated reference palette: one blue series,
/// hairline neutral grid, text in ink tokens (never the series color), fixed status colors.
enum Ink {
    static let surface   = NSColor(hex: 0xfcfcfb)
    static let header    = NSColor(hex: 0xf0efec)
    static let primary   = NSColor(hex: 0x0b0b0b)
    static let secondary = NSColor(hex: 0x52514e)
    static let muted     = NSColor(hex: 0x898781)
    static let grid      = NSColor(hex: 0xe1e0d9)
    static let baseline  = NSColor(hex: 0xc3c2b7)
    static let series    = NSColor(hex: 0x2a78d6)
    static let warning   = NSColor(hex: 0xfab219)
    static let critical  = NSColor(hex: 0xd03b3b)

    static var theme: WidgetTheme {
        WidgetTheme(body: surface, header: header, border: NSColor.black.withAlphaComponent(0.10),
                    title: secondary, buttonTint: muted)
    }

    enum Level { case normal, warning, critical }

    static func level(for percent: Double) -> Level {
        if percent >= Double(UsageSettings.criticalLevel) { return .critical }
        if percent >= Double(UsageSettings.warningLevel) { return .warning }
        return .normal
    }

    static func color(for level: Level) -> NSColor {
        switch level {
        case .normal: return series
        case .warning: return warning
        case .critical: return critical
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}
