import SwiftUI

// ── Color tokens ──────────────────────────────────────────────────────────────

extension Color {
    // Brand
    static let brandGreen    = Color(hex: "#1D9E75")
    static let brandGreenBg  = Color(hex: "#E1F5EE")
    static let brandPurple   = Color(hex: "#7F77DD")
    static let brandPurpleBg = Color(hex: "#EEEDFE")

    // Semantic
    static let success   = Color(hex: "#1D9E75")
    static let warning   = Color(hex: "#BA7517")
    static let danger    = Color(hex: "#E24B4A")
    static let infoBg    = Color(hex: "#E6F1FB")
    static let infoText  = Color(hex: "#185FA5")

    // Neutrals
    static let surface   = Color(hex: "#F1EFE8") // secondary background
    static let border    = Color(hex: "#D3D1C7")
    static let textMuted = Color(hex: "#888780")

    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

// ── Typography ────────────────────────────────────────────────────────────────

extension Font {
    static let titleLg   = Font.system(size: 24, weight: .semibold)
    static let titleMd   = Font.system(size: 20, weight: .semibold)
    static let titleSm   = Font.system(size: 17, weight: .semibold)
    static let bodyLg    = Font.system(size: 16, weight: .regular)
    static let bodyMd    = Font.system(size: 14, weight: .regular)
    static let bodySm    = Font.system(size: 12, weight: .regular)
    static let labelMd   = Font.system(size: 14, weight: .medium)
    static let labelSm   = Font.system(size: 12, weight: .medium)
    static let numericLg = Font.system(size: 32, weight: .semibold, design: .rounded)
    static let numericMd = Font.system(size: 22, weight: .semibold, design: .rounded)
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
    static let sm: CGFloat  =  8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 16
    static let pill: CGFloat = 100
}

// ── Shadows ───────────────────────────────────────────────────────────────────

extension View {
    func cardShadow() -> some View {
        self.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}
