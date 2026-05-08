import SwiftUI

// ── Water tracker ────────────────────────────────────────────────────────────
// Local-only hydration tracking with per-day history. Each day's count is
// stored under a date-scoped UserDefaults key (`water_glasses_YYYY-MM-DD`)
// so the dashboard can show what was logged on past days. Today is the only
// day that's editable; past/future days are read-only.

@Observable
@MainActor
final class WaterTracker {
    static let shared = WaterTracker()

    var goal: Int = 8                // glasses per day (~250 ml × 8 = 2 L)
    var glasses: Int = 0             // glasses for the currently-viewed date
    var viewingDate: Date = Calendar.current.startOfDay(for: Date())

    private let goalKey = "water_goal"

    init() {
        load()
    }

    /// True when the tracker is showing today's data and the user can edit it.
    var isViewingToday: Bool { Calendar.current.isDateInToday(viewingDate) }

    func add(_ n: Int = 1) {
        // Only today's count is mutable. Past days are historical record;
        // future days haven't happened.
        guard isViewingToday else { return }
        glasses = min(max(glasses + n, 0), 99)
        persist(glasses, for: viewingDate)
        Haptics.impact(.light)
    }

    func reset() {
        glasses = 0
        persist(0, for: viewingDate)
    }

    /// Switch the tracker to display a different day's water count. Read-only
    /// for past/future dates; write-enabled when it's today.
    func loadForDate(_ date: Date) {
        viewingDate = Calendar.current.startOfDay(for: date)
        glasses = readCount(for: viewingDate)
    }

    /// Re-read from UserDefaults. Used after sign-out clears keys so the
    /// in-memory singleton snaps back without an app restart.
    func reloadFromDefaults() {
        goal = 8
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
        // Default to today's count.
        viewingDate = Calendar.current.startOfDay(for: Date())
        glasses = readCount(for: viewingDate)
    }

    private func readCount(for date: Date) -> Int {
        UserDefaults.standard.integer(forKey: countKey(for: date))
    }

    private func persist(_ count: Int, for date: Date) {
        UserDefaults.standard.set(count, forKey: countKey(for: date))
    }

    private func countKey(for date: Date) -> String {
        "water_glasses_\(dateKey(date))"
    }

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// ── Water card ───────────────────────────────────────────────────────────────
// Compact card for the Home dashboard. Read-only when viewing past/future
// days (the +/- buttons hide and a status line clarifies the state).

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
                    statusLabel
                    Spacer()
                    if tracker.isViewingToday {
                        HStack(spacing: Spacing.xs) {
                            stepperButton(icon: "minus", enabled: tracker.glasses > 0) {
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
    }

    @ViewBuilder
    private var statusLabel: some View {
        if !tracker.isViewingToday {
            Label("Read only for past days", systemImage: "lock")
                .font(.bodySm)
                .foregroundColor(.textMuted)
        } else if tracker.fraction >= 1 {
            Label("Goal hit today", systemImage: "checkmark.seal.fill")
                .font(.labelSm)
                .foregroundColor(.accentSky)
        } else {
            Text("Tap a glass to log")
                .font(.bodySm)
                .foregroundColor(.textMuted)
        }
    }

    /// Big circular button to make hit targets obvious.
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
                    // Tap-to-set only works for today. Read-only on past/future.
                    guard tracker.isViewingToday else { return }
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
                .disabled(!tracker.isViewingToday)
            }
            Spacer(minLength: 0)
        }
    }
}
