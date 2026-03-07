import Cocoa

enum Theme {
    // Panel
    static let panelBackground = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.95)
    static let panelBorder = NSColor(white: 0.25, alpha: 1)
    static let panelCornerRadius: CGFloat = 12

    // Accent (unified cyan)
    static let accent = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
    static let accentDim = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.7)

    // Text hierarchy
    static let textPrimary = NSColor(white: 0.9, alpha: 1)
    static let textSecondary = NSColor(white: 0.55, alpha: 1) // WCAG AA on panelBackground
    static let textTertiary = NSColor(white: 0.4, alpha: 1)
    static let textHover = NSColor(white: 0.75, alpha: 1)

    // Controls
    static let controlDim = NSColor(white: 0.5, alpha: 1)
    static let separator = NSColor(white: 0.3, alpha: 0.2)

    // Semantic
    static let success = NSColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 1)

    // Related terms (accent family)
    static let relatedText = accentDim
    static let relatedHover = accent
    static let relatedDot = NSColor(white: 0.35, alpha: 1)
}
