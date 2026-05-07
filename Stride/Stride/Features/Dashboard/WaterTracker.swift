import SwiftUI

// ── Water tracker ────────────────────────────────────────────────────────────
// Local-only hydration tracking: glass count per local-day, persisted in
// UserDefaults so it survives relaunches. No backend round-trip needed for
// such a high-frequency, low-stakes interaction. We can sync later if
// cross-device hydration becomes a real ask.

@Observable
@MainActor
final class WaterTracker {
    static let shared = WaterTracker()

    var goal: Int = 8       // glasses per day (≈ 250 ml × 8 = 2 L)
    var glasses: Int = 0    // glasses consumed today

    private let dateKey = "water_date"
    private let countKey = "water_glasses"
    private let goalKey  = "water_goal"

    init() {
        load()
    }

    func add(_ n: Int = 1) {
        rolloverIfNeeded()
        glasses = min(max(glasses + n, 0), 99)
        persist()
        Haptics.impact(.light)
    }

    func reset() {
        glasses = 0
        persist()
    }

    /// Re-read from UserDefaults. Used after sign-out clears the keys so the
    /// in-memory singleton snaps back to a clean slate without an app restart.
    func reloadFromDefaults() {
        goal = 8
        glasses = 0
        load()
    }

    func setGoal(_ g: Int) {
        goal = max(1, min(g, 30))
        UserDefaults.standard.set(goal, forKey: goalKey)
    }

    var fraction: Double { goal == 0 ? 0 : min(Double(glasses) / Double(goal), 1) }
    var litres: Double { Double(glasses) * 0.25 }

    private func load() {
        let saved = UserDefaults.standard.integer(forKey: goalKey)
        if saved > 0 { goal = saved }
        rolloverIfNeeded()
        glasses = UserDefaults.standard.integer(forKey: countKey)
    }

    private func persist() {
        UserDefaults.standard.set(glasses, forKey: countKey)
        UserDefaults.standard.set(todayKey(), forKey: dateKey)
    }

    private func rolloverIfNeeded() {
        let today = todayKey()
        let last = UserDefaults.standard.string(forKey: dateKey)
        if last != today {
            glasses = 0
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
    }

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// ── Water card ───────────────────────────────────────────────────────────────
// Compact card for the Home dashboard. Glass dots on the left, +/- on the
// right. Tapping the card itself increments by 1 (most common action).

struct WaterCard: View {
    @Bindable var tracker: WaterTracker

    var body: some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .foregroundColor(.accentSky)
                            .font(.system(size: 14, weight: .semibold))
                        Text("Water")
                            .font(.labelMd)
                    }
                    Spacer()
                    Text(countLabel)
                        .font(.bodySm)
                        .foregroundColor(.textMuted)
                        .contentTransition(.numericText())
                }

                glassRow

                HStack {
                    if tracker.fraction >= 1 {
                        Label("Goal hit today", systemImage: "checkmark.seal.fill")
                            .font(.labelSm)
                            .foregroundColor(.accentSky)
                    } else {
                        Text("Tap a glass to log")
                            .font(.bodySm)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    HStack(spacing: Spacing.xs) {
                        stepperButton(
                            icon: "minus",
                            enabled: tracker.glasses > 0
                        ) {
                            if tracker.glasses > 0 { tracker.add(-1) }
                        }
                        stepperButton(icon: "plus", enabled: true) {
                            tracker.add(1)
                        }
                    }
                }
            }
        }
    }

    /// Big circular button to make hit targets obvious. The original 32×30
    /// inline pair was too small — testers couldn't reliably tap the minus.
    private func stepperButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(enabled ? .white : Color.textMuted)
                .frame(width: 40, height: 40)
                .background(enabled ? Color.accentSky : Color.accentSky.opacity(0.18))
                .clipShape(Circle())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    /// Cleaner copy when over goal — "12 of 8" reads weirdly.
    private var countLabel: String {
        let litres = String(format: "%.2f L", tracker.litres)
        if tracker.glasses > tracker.goal {
            let over = tracker.glasses - tracker.goal
            return "\(tracker.goal)/\(tracker.goal) +\(over) · \(litres)"
        }
        return "\(tracker.glasses) of \(tracker.goal) · \(litres)"
    }

    private var glassRow: some View {
        let count = max(tracker.goal, 1)
        return HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Button {
                    // Tapping a glass sets the count up to (or back down through) it.
                    let target = i + 1
                    let delta  = target - tracker.glasses
                    if delta != 0 { tracker.add(delta) }
                } label: {
                    Image(systemName: i < tracker.glasses ? "drop.fill" : "drop")
                        .font(.system(size: 18))
                        .foregroundColor(i < tracker.glasses ? .accentSky : Color.accentSky.opacity(0.35))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
