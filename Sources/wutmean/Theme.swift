import Cocoa

/// Available font families for user selection
enum FontFamily: String, CaseIterable {
    case systemMono = "system-mono"
    case systemSans = "system-sans"
    case systemSerif = "system-serif"
    case systemRounded = "system-rounded"
    case menlo = "Menlo"
    case jetBrainsMono = "JetBrainsMono-Regular"
    case inter = "Inter"

    var displayName: String {
        switch self {
        case .systemMono: return "System Mono"
        case .systemSans: return "System Sans"
        case .systemSerif: return "System Serif"
        case .systemRounded: return "System Rounded"
        case .menlo: return "Menlo"
        case .jetBrainsMono: return "JetBrains Mono"
        case .inter: return "Inter"
        }
    }

    /// Whether this font family is available on the current system
    var isAvailable: Bool {
        switch self {
        case .systemMono, .systemSans, .systemSerif, .systemRounded:
            return true
        case .menlo:
            return NSFont(name: "Menlo", size: 12) != nil
        case .jetBrainsMono:
            return NSFont(name: "JetBrainsMono-Regular", size: 12) != nil
        case .inter:
            return NSFont(name: "Inter", size: 12) != nil
        }
    }

    /// Resolve to an NSFont at the given size and weight
    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .systemMono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .systemSans:
            return .systemFont(ofSize: size, weight: weight)
        case .systemSerif:
            if let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.serif) {
                return NSFont(descriptor: descriptor, size: size)
                    ?? .systemFont(ofSize: size, weight: weight)
            }
            return .systemFont(ofSize: size, weight: weight)
        case .systemRounded:
            let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            if let rounded = descriptor.withDesign(.rounded) {
                return NSFont(descriptor: rounded, size: size)
                    ?? .systemFont(ofSize: size, weight: weight)
            }
            return .systemFont(ofSize: size, weight: weight)
        case .menlo, .jetBrainsMono:
            if let font = NSFont(name: rawValue, size: size) {
                return font
            }
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .inter:
            if let font = NSFont(name: rawValue, size: size) {
                return font
            }
            // Inter is sans-serif — fall back to system sans, not mono
            return .systemFont(ofSize: size, weight: weight)
        }
    }

    /// All families that are actually usable on this machine
    static var available: [FontFamily] {
        allCases.filter { $0.isAvailable }
    }
}

enum Theme {
    static var darkMode = true
    static var fontFamily: FontFamily = .systemMono
    static var fontSize: CGFloat = 12

    // Panel
    static var panelBackground: NSColor {
        darkMode
            ? NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 0.97)
            : NSColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 0.97)
    }
    static var panelBorder: NSColor {
        darkMode
            ? NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
            : NSColor(red: 0.82, green: 0.81, blue: 0.79, alpha: 1)
    }
    static let panelCornerRadius: CGFloat = 4

    // Header band — amber works on both modes
    static let headerBackground = NSColor(red: 0.83, green: 0.54, blue: 0.21, alpha: 1)
    static let headerText = NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)

    // Accent
    static let accent = NSColor(red: 0.83, green: 0.54, blue: 0.21, alpha: 1)
    static let accentDim = NSColor(red: 0.83, green: 0.54, blue: 0.21, alpha: 0.50)

    // Text
    static var textPrimary: NSColor {
        darkMode
            ? NSColor(red: 0.88, green: 0.88, blue: 0.86, alpha: 1)
            : NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    }
    static var textSecondary: NSColor {
        darkMode
            ? NSColor(red: 0.50, green: 0.50, blue: 0.48, alpha: 1)
            : NSColor(red: 0.42, green: 0.42, blue: 0.40, alpha: 1)
    }
    static var textTertiary: NSColor {
        darkMode
            ? NSColor(red: 0.35, green: 0.35, blue: 0.34, alpha: 1)
            : NSColor(red: 0.58, green: 0.58, blue: 0.56, alpha: 1)
    }
    static var textHover: NSColor { accent }

    // Controls
    static var controlDim: NSColor {
        darkMode
            ? NSColor(red: 0.42, green: 0.42, blue: 0.40, alpha: 1)
            : NSColor(red: 0.65, green: 0.65, blue: 0.63, alpha: 1)
    }
    static var fieldBackground: NSColor {
        darkMode
            ? NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor.white
    }
    static var buttonSecondaryBackground: NSColor {
        darkMode
            ? NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
            : NSColor(red: 0.88, green: 0.87, blue: 0.85, alpha: 1)
    }

    // Example level explanation text
    static var exampleExplainText: NSColor {
        darkMode
            ? textSecondary
            : NSColor(red: 0.50, green: 0.49, blue: 0.47, alpha: 1)
    }
    static var separator: NSColor {
        darkMode
            ? NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 0.7)
            : NSColor(red: 0.80, green: 0.80, blue: 0.78, alpha: 0.7)
    }

    // Semantic
    static var success: NSColor {
        darkMode
            ? NSColor(red: 0.35, green: 0.67, blue: 0.39, alpha: 1)
            : NSColor(red: 0.22, green: 0.55, blue: 0.26, alpha: 1)
    }

    // Related terms
    static var relatedText: NSColor {
        darkMode
            ? NSColor(red: 0.58, green: 0.70, blue: 0.37, alpha: 0.90)
            : NSColor(red: 0.30, green: 0.50, blue: 0.15, alpha: 0.90)
    }
    static var relatedHover: NSColor {
        darkMode
            ? NSColor(red: 0.58, green: 0.70, blue: 0.37, alpha: 1)
            : NSColor(red: 0.30, green: 0.50, blue: 0.15, alpha: 1)
    }
    static var relatedDot: NSColor { textTertiary }

    // Typography — resolved through fontFamily + fontSize scaling
    //
    // The base size is 12pt. When fontSize is different, all sizes scale proportionally.
    // e.g. fontSize=14 → a call for size 12 returns 14, size 11 returns ~12.8

    /// Scale a point size relative to the configured fontSize (base 12)
    static func scaled(_ size: CGFloat) -> CGFloat {
        (size / 12.0) * fontSize
    }

    static func displayFont(size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        fontFamily.font(size: size, weight: weight)
    }

    /// Body font — the ONLY font affected by fontSize scaling
    static func bodyFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        fontFamily.font(size: scaled(size), weight: weight)
    }

    static func monoFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        fontFamily.font(size: size, weight: weight)
    }

    /// Fixed-size font that ignores fontSize scaling (for Settings UI controls)
    static func fixedFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        fontFamily.font(size: size, weight: weight)
    }
}
