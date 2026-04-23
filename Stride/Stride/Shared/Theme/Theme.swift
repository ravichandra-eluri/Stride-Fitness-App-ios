import SwiftUI
import UIKit

// ── Color tokens ──────────────────────────────────────────────────────────────
// Every token resolves dynamically for light / dark. Use the named tokens in
// views — never reach for a raw hex value at the call site.

extension Color {
    // Brand
    static let brandGreen    = Color(light: "#1D9E75", dark: "#3BBF92")
    static let brandGreenBg  = Color(light: "#E1F5EE", dark: "#163A30")
    static let brandPurple   = Color(light: "#7F77DD", dark: "#A9A3F0")
    static let brandPurpleBg = Color(light: "#EEEDFE", dark: "#2A2660")

    // Semantic
    static let success   = Color(light: "#1D9E75", dark: "#3BBF92")
    static let warning   = Color(light: "#BA7517", dark: "#E2A24C")
    static let danger    = Color(light: "#E24B4A", dark: "#FF6B6A")
    static let infoBg    = Color(light: "#E6F1FB", dark: "#10324F")
    static let infoText  = Color(light: "#185FA5", dark: "#6FB6FF")

    // Surfaces — resolve to the system grouped-background palette so cards
    // read correctly in both color schemes without hand-tuned hex values.
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let cardSurface   = Color(uiColor: .secondarySystemGroupedBackground)
    static let surface       = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border        = Color(uiColor: .separator)
    static let textMuted     = Color(uiColor: .secondaryLabel)

    /// Build a dynamic color that switches between light and dark values.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }

    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}

// ── Typography ────────────────────────────────────────────────────────────────
// Prefer text-style based fonts so the app honors the user's Dynamic Type
// setting. Numeric tokens stay at a fixed scale for ring / big-number layouts.

extension Font {
    static let titleLg   = Font.system(.title, design: .default).weight(.semibold)
    static let titleMd   = Font.system(.title2, design: .default).weight(.semibold)
    static let titleSm   = Font.system(.headline, design: .default)
    static let bodyLg    = Font.system(.body)
    static let bodyMd    = Font.system(.subheadline)
    static let bodySm    = Font.system(.footnote)
    static let labelMd   = Font.system(.subheadline).weight(.medium)
    static let labelSm   = Font.system(.footnote).weight(.medium)
    static let numericLg = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let numericMd = Font.system(size: 24, weight: .semibold, design: .rounded)
}

// ── Spacing ───────────────────────────────────────────────────────────────────

enum Spacing {
    static let xs: CGFloat  =  4
    static let sm: CGFloat  =  8
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 48
}

// ── Corner radius ─────────────────────────────────────────────────────────────

enum Radius {
    static let sm: CGFloat  = 10
    static let md: CGFloat  = 14
    static let lg: CGFloat  = 20
    static let pill: CGFloat = 100
}

// ── Shadows ───────────────────────────────────────────────────────────────────

extension View {
    func cardShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

// ── Haptics ───────────────────────────────────────────────────────────────────
// Small, consistent wrapper so views don't each reinvent generator plumbing.

enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
