import SwiftUI

// ── WCard — standard card container ──────────────────────────────────────────

struct WCard<Content: View>: View {
    var padding: CGFloat = Spacing.md
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.border, lineWidth: 0.5)
            )
            .cardShadow()
    }
}

// ── WButton — primary CTA ─────────────────────────────────────────────────────

struct WButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(.labelMd)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.brandGreen)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .disabled(isLoading)
    }
}

// ── WButtonOutline ────────────────────────────────────────────────────────────

struct WButtonOutline: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.labelMd)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
    }
}

// ── WChip — selectable pill ───────────────────────────────────────────────────

struct WChip: View {
    let label: String
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.labelSm)
                .foregroundColor(isSelected ? .infoText : .textMuted)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.infoBg : Color.surface)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.infoText.opacity(0.4) : Color.border,
                                lineWidth: 0.5)
                )
                .clipShape(Capsule())
        }
    }
}

// ── WStatCard — metric display ────────────────────────────────────────────────

struct WStatCard: View {
    let value: String
    let label: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.numericMd)
                .foregroundColor(valueColor)
            Text(label)
                .font(.bodySm)
                .foregroundColor(.textMuted)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}

// ── WCalorieRing — circular progress ─────────────────────────────────────────

struct WCalorieRing: View {
    let eaten: Int
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(eaten) / Double(target), 1.0)
    }

    private var remaining: Int { max(target - eaten, 0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.border, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress >= 1.0 ? Color.danger : Color.brandGreen,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
            VStack(spacing: 0) {
                Text("\(remaining)")
                    .font(.numericMd)
                    .foregroundColor(.primary)
                Text("left")
                    .font(.bodySm)
                    .foregroundColor(.textMuted)
            }
        }
    }
}

// ── WMacroRow — protein/carbs/fat bar ────────────────────────────────────────

struct WMacroRow: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: Spacing.lg) {
            macroItem(label: "Protein", value: protein, color: .brandPurple)
            macroItem(label: "Carbs",   value: carbs,   color: .brandGreen)
            macroItem(label: "Fat",     value: fat,     color: .warning)
        }
    }

    private func macroItem(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value))g")
                .font(.labelMd)
                .foregroundColor(color)
            Text(label)
                .font(.bodySm)
                .foregroundColor(.textMuted)
        }
    }
}

// ── WCoachBubble ──────────────────────────────────────────────────────────────

struct WCoachBubble: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.infoBg)
                    .frame(width: 32, height: 32)
                Text("AI")
                    .font(.labelSm)
                    .foregroundColor(.infoText)
            }
            Text(message)
                .font(.bodyMd)
                .foregroundColor(.primary)
                .padding(Spacing.md)
                .background(Color.surface)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: Radius.sm,
                        bottomTrailingRadius: Radius.sm, topTrailingRadius: Radius.sm
                    )
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

// ── WErrorView ────────────────────────────────────────────────────────────────

struct WErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Something went wrong")
                .font(.titleSm)
            Text(message)
                .font(.bodyMd)
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
            WButton(title: "Try again", action: retry)
                .frame(width: 160)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
