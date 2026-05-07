import SwiftUI

// ── Streak celebration ───────────────────────────────────────────────────────
// Tracks which streak milestones have been celebrated locally so we only fire
// the confetti+haptic once per milestone, not every dashboard load.
//
// Milestones: 3, 7, 14, 30, 60, 90, 180, 365 days. Each is a meaningful habit
// landmark; firing on every increment would dilute the dopamine.

@Observable
@MainActor
final class StreakCelebrator {
    static let shared = StreakCelebrator()

    static let milestones = [3, 7, 14, 30, 60, 90, 180, 365]
    private let key = "streak_celebrated_milestones"

    /// The currently-displayed celebration. Set non-nil to show the overlay,
    /// nil to dismiss.
    var active: Milestone? = nil

    struct Milestone: Identifiable, Equatable {
        let id = UUID()
        let days: Int
        var title: String { "\(days)-day streak" }
        var subtitle: String {
            switch days {
            case 3:   return "Habit forming. Keep going."
            case 7:   return "A full week. You're locked in."
            case 14:  return "Two weeks strong."
            case 30:  return "One whole month. Massive."
            case 60:  return "Sixty days. The plan is the lifestyle now."
            case 90:  return "Three months. This is who you are."
            case 180: return "Half a year. Inspiring."
            case 365: return "A full year. Legend."
            default:  return "Keep showing up."
            }
        }
        var emoji: String {
            switch days {
            case ..<7:  return "🔥"
            case ..<30: return "🚀"
            case ..<90: return "💪"
            default:    return "🏆"
            }
        }
    }

    /// Call when streak count is known. Fires the celebration if a new
    /// milestone was just crossed (and hasn't been celebrated before).
    func evaluate(streakDays: Int) {
        guard let m = Self.milestones.first(where: { $0 == streakDays }) else { return }
        var celebrated = celebratedSet()
        if celebrated.contains(m) { return }
        celebrated.insert(m)
        UserDefaults.standard.set(Array(celebrated), forKey: key)

        Haptics.notify(.success)
        active = Milestone(days: m)
    }

    func dismiss() { active = nil }

    private func celebratedSet() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
    }
}

// ── Overlay view ─────────────────────────────────────────────────────────────
// Big card slides up from center with confetti dots floating up behind it.
// Tap anywhere to dismiss.

struct StreakCelebrationOverlay: View {
    @Bindable var celebrator: StreakCelebrator

    var body: some View {
        ZStack {
            if let m = celebrator.active {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { celebrator.dismiss() } }
                    .transition(.opacity)

                ConfettiBurst()
                    .transition(.opacity)

                VStack(spacing: Spacing.md) {
                    Text(m.emoji)
                        .font(.system(size: 64))
                    Text(m.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(m.subtitle)
                        .font(.bodyMd)
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                    WButton(title: "Keep going") {
                        withAnimation { celebrator.dismiss() }
                    }
                    .frame(maxWidth: 240)
                    .padding(.top, Spacing.xs)
                }
                .padding(Spacing.xl)
                .background(
                    LinearGradient(
                        colors: [Color.cardSurface, Color.brandGreenBg.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(Color.brandGreen.opacity(0.4), lineWidth: 1)
                )
                .heroShadow()
                .padding(Spacing.lg)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: celebrator.active)
    }
}

// Cheap confetti: 30 colored circles drifting up with random horizontal sway.
private struct ConfettiBurst: View {
    @State private var animate = false
    private let colors: [Color] = [.brandGreen, .brandPurple, .warning, .accentPeach, .accentSky]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<30, id: \.self) { i in
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: 8, height: 8)
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: animate
                                ? -20
                                : geo.size.height + 20
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: Double.random(in: 1.4...2.6))
                                .delay(Double(i) * 0.02),
                            value: animate
                        )
                }
            }
            .onAppear { animate = true }
        }
    }
}
