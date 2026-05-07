import SwiftUI

struct WScreenBackground<Content: View>: View {
    /// Optional tint color layered over the base background. Each tab passes
    /// its own (Color.tintHome, .tintMeals, .tintCoach, .tintProgress) so
    /// tabs feel distinct without losing brand consistency.
    var tint: Color = .brandGreenBg
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.appBackground,
                    tint.opacity(0.7),
                    Color.brandPurpleBg.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentPeach.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 14)
                .offset(x: 130, y: -280)

            Circle()
                .fill(Color.accentMint.opacity(0.24))
                .frame(width: 220, height: 220)
                .blur(radius: 12)
                .offset(x: -140, y: -120)

            content()
        }
    }
}

// ── WTabBackground — convenience tinted background applied per tab ──────────

struct WTabBackground: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.appBackground,
                    tint.opacity(0.55),
                    Color.appBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            content
        }
    }
}

extension View {
    /// Apply a tinted background to a tab's root view. Subtle gradient overlay
    /// that disambiguates tabs without abandoning the brand palette.
    func tabBackground(_ tint: Color) -> some View {
        modifier(WTabBackground(tint: tint))
    }
}

struct WHeroCard<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [Color.cardSurface.opacity(0.94), Color.brandGreenBg.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .heroShadow()
    }
}

struct WSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(eyebrow.uppercased())
                .font(.labelSm)
                .foregroundColor(.brandGreen)
            Text(title)
                .font(.titleLg)
            Text(subtitle)
                .font(.bodyMd)
                .foregroundColor(.textMuted)
        }
    }
}

// ── WCard — standard card container ──────────────────────────────────────────

struct WCard<Content: View>: View {
    var padding: CGFloat = Spacing.md
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.border.opacity(0.6), lineWidth: 0.5)
            )
            .cardShadow()
    }
}

// ── WButton — primary CTA ─────────────────────────────────────────────────────

struct WButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.9)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(title)
                    .font(.labelMd)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.brandGreen, Color.brandGreen.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .shadow(color: Color.brandGreen.opacity(0.25), radius: 8, x: 0, y: 4)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading || !isEnabled)
    }
}

// Subtle scale/opacity reaction on press for every primary button.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// ── WButtonOutline ────────────────────────────────────────────────────────────

struct WButtonOutline: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title).font(.labelMd)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// ── WChip — selectable pill ───────────────────────────────────────────────────

struct WChip: View {
    let label: String
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            Text(label)
                .font(.labelSm)
                .foregroundColor(isSelected ? .white : .textMuted)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.brandGreen : Color.surface)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.border, lineWidth: 0.5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// ── WStatCard — metric display ────────────────────────────────────────────────

struct WStatCard: View {
    let value: String
    let label: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(value)
                .font(.numericMd)
                .foregroundColor(valueColor)
            Text(label)
                .font(.bodySm)
                .foregroundColor(.textMuted)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.border.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// ── WCalorieRing — circular progress ─────────────────────────────────────────
// Gradient stroke that shifts from green → amber → red as the user approaches
// and then exceeds their goal. Lightly animated when progress changes.

struct WCalorieRing: View {
    let eaten: Int
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return Double(eaten) / Double(target)
    }

    private var clampedProgress: Double { min(progress, 1.0) }
    private var remaining: Int { max(target - eaten, 0) }
    private var over: Int { max(eaten - target, 0) }
    private var isOver: Bool { progress > 1.0 }

    private var ringColors: [Color] {
        if isOver          { return [.danger, .warning] }
        if progress >= 0.9 { return [.warning, .brandGreen] }
        return [.brandGreen, .brandGreen.opacity(0.8)]
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.border.opacity(0.4), lineWidth: 10)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AngularGradient(
                        colors: ringColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: clampedProgress)

            VStack(spacing: 0) {
                Text("\(isOver ? over : remaining)")
                    .font(.numericMd)
                    .foregroundColor(isOver ? .danger : .primary)
                    .contentTransition(.numericText())
                Text(isOver ? "over" : "left")
                    .font(.bodySm)
                    .foregroundColor(.textMuted)
            }
        }
    }
}

// ── WGlassCard — frosted gradient card (Stride signature) ───────────────────

struct WGlassCard<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        Color.cardSurface.opacity(0.95),
                        Color.brandGreenBg.opacity(0.55),
                        Color.brandPurpleBg.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(
                        LinearGradient(
                            colors: [Color.brandGreen.opacity(0.35), Color.brandPurple.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .cardShadow()
    }
}

// ── WMacroBar — horizontal labeled progress bar ─────────────────────────────

struct WMacroBar: View {
    let label: String
    let eaten: Double
    let target: Double
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(eaten / target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                Spacer()
                Text("\(Int(eaten))/\(Int(target))g")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.18))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 6)
        }
    }
}

// ── WHeroCalorieCard — big "calories left" hero with side ring ───────────────

struct WHeroCalorieCard: View {
    let eaten: Int
    let target: Int

    private var remaining: Int { max(target - eaten, 0) }
    private var over: Int { max(eaten - target, 0) }
    private var isOver: Bool { eaten > target }
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(eaten) / Double(target), 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(isOver ? over : remaining)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(isOver ? .danger : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isOver ? "Calories over" : "Calories left")
                    .font(.labelMd)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.border.opacity(0.35), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isOver ? Color.danger : Color.brandGreen,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isOver ? .danger : .primary)
            }
            .frame(width: 84, height: 84)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.border.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// ── WMacroLeftCard — single macro tile with circular progress ────────────────

struct WMacroLeftCard: View {
    let label: String
    let eaten: Double
    let target: Double
    let icon: String
    let color: Color

    private var remaining: Int { max(Int(target) - Int(eaten), 0) }
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(eaten / target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(remaining)g")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                Text("\(label) left")
                    .font(.bodySm)
                    .foregroundColor(.textMuted)
            }
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.border.opacity(0.35), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 44, height: 44)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(Color.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.border.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// ── WMacroRow — protein/carbs/fat bar ────────────────────────────────────────

struct WMacroRow: View {
    let protein: Double
    var proteinTarget: Double = 0
    let carbs: Double
    var carbsTarget: Double = 0
    let fat: Double
    var fatTarget: Double = 0

    var body: some View {
        HStack(spacing: Spacing.lg) {
            macroItem(label: "Protein", value: protein, target: proteinTarget, color: .brandPurple)
            macroItem(label: "Carbs",   value: carbs,   target: carbsTarget,   color: .brandGreen)
            macroItem(label: "Fat",     value: fat,     target: fatTarget,     color: .warning)
        }
    }

    private func macroItem(label: String, value: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            if target > 0 {
                Text("\(Int(value))/\(Int(target))g")
                    .font(.labelMd)
                    .foregroundColor(color)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * min(value / target, 1), height: 4)
                    }
                }
                .frame(height: 4)
            } else {
                Text("\(Int(value))g")
                    .font(.labelMd)
                    .foregroundColor(color)
            }
            Text(label)
                .font(.bodySm)
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// ── WCoachBubble ──────────────────────────────────────────────────────────────

struct WCoachBubble: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.brandPurple, Color.brandGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(message)
                .font(.bodyMd)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.md)
                .background(Color.cardSurface)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2, bottomLeadingRadius: Radius.md,
                        bottomTrailingRadius: Radius.md, topTrailingRadius: Radius.md,
                        style: .continuous
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2, bottomLeadingRadius: Radius.md,
                        bottomTrailingRadius: Radius.md, topTrailingRadius: Radius.md,
                        style: .continuous
                    )
                    .stroke(Color.border.opacity(0.5), lineWidth: 0.5)
                )
        }
    }
}

// ── WLoadingView ──────────────────────────────────────────────────────────────

struct WLoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.bodyMd)
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── WSkeleton — shimmering placeholder for content-loading states ───────────
// Use to mimic the shape of the upcoming content while it loads (Home cards,
// Meal plan day rows). Feels more premium than a centered spinner.

struct WSkeleton: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 6
    @State private var phase: CGFloat = -0.6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.border.opacity(0.18))
            .frame(height: height)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear,                        location: phase),
                        .init(color: Color.white.opacity(0.55),     location: phase + 0.2),
                        .init(color: .clear,                        location: phase + 0.4),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

/// Card-shaped skeleton that mimics the WCard footprint.
struct WSkeletonCard: View {
    var lines: Int = 3
    var body: some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(0..<lines, id: \.self) { i in
                    WSkeleton(height: i == 0 ? 22 : 14)
                        .frame(width: i == lines - 1 ? 160 : nil, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// ── WErrorView ────────────────────────────────────────────────────────────────

struct WErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.warning)
            Text("Something went wrong")
                .font(.titleSm)
            Text(message)
                .font(.bodyMd)
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
            WButton(title: "Try again", icon: "arrow.clockwise", action: retry)
                .frame(width: 200)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── WEmptyState ──────────────────────────────────────────────────────────────
// Consistent empty-state scaffold used across tabs. Gradient badge + soft
// pulse animation gives empty screens delight instead of flatness.

struct WEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil
    /// Tint pair for the gradient badge. Defaults to brand green→purple.
    var tintColors: [Color] = [.brandGreen, .brandPurple]
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(tintColors.first?.opacity(0.18) ?? Color.brandGreen.opacity(0.18), lineWidth: 1)
                    .frame(width: pulse ? 112 : 88, height: pulse ? 112 : 88)
                    .opacity(pulse ? 0 : 1)

                Circle()
                    .fill(
                        LinearGradient(colors: tintColors,
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: (tintColors.first ?? .brandGreen).opacity(0.25), radius: 12, x: 0, y: 6)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            Text(title).font(.titleSm)
            Text(subtitle)
                .font(.bodyMd)
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let ctaTitle, let ctaAction {
                WButton(title: ctaTitle, action: ctaAction)
                    .frame(maxWidth: 240)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
