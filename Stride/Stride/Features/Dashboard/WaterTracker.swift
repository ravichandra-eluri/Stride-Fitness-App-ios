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
                    Text("\(tracker.glasses) of \(tracker.goal) · \(String(format: "%.2f L", tracker.litres))")
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
                    HStack(spacing: 0) {
                        Button {
                            if tracker.glasses > 0 { tracker.add(-1) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 30)
                                .foregroundColor(tracker.glasses == 0 ? .textMuted : .accentSky)
                        }
                        .disabled(tracker.glasses == 0)
                        .buttonStyle(.plain)

                        Button {
                            tracker.add(1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 30)
                                .foregroundColor(.accentSky)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color.accentSky.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentSky.opacity(0.3), lineWidth: 1))
                }
            }
        }
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
