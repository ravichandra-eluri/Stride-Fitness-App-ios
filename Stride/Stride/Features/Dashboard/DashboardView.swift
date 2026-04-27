import SwiftUI

// ── Main tab bar ──────────────────────────────────────────────────────────────

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            MealPlanView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(1)

            LogFoodView(onLogged: {
                // Jump back to Home so the user sees their updated totals.
                withAnimation { selectedTab = 0 }
            })
                .tabItem { Label("Log", systemImage: "plus.circle.fill") }
                .tag(2)

            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.fill") }
                .tag(3)

            ProgressTrackingView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(4)
        }
        .tint(Color.brandGreen)
        .onChange(of: selectedTab) { _, _ in
            Haptics.selection()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }
}

// ── Dashboard ViewModel ───────────────────────────────────────────────────────

@Observable
@MainActor

class DashboardViewModel {
    var todayLog: TodayLogResponse?
    var coachMessage: CoachMessage?
    var profile: UserProfile?
    var weightHistory: [WeightEntry] = []
    var isLoading = true

    func load() async {
        isLoading = true

        // Load log and profile in parallel (fast DB queries)
        async let logTask     = try? APIClient.shared.getTodayLog()
        async let profileTask = try? APIClient.shared.getProfile()
        todayLog = await logTask
        profile  = await profileTask
        isLoading = false

        // Secondary loads — run after UI is visible, order doesn't matter
        async let coachTask   = try? APIClient.shared.getTodayCoachMessage()
        async let weightsTask = try? APIClient.shared.getWeightHistory()
        coachMessage   = await coachTask
        let raw = await weightsTask ?? []
        weightHistory  = raw.sorted { $0.loggedAtDate < $1.loggedAtDate }
    }

    var caloriesEaten: Int { todayLog?.log?.caloriesEaten ?? 0 }
    var calorieTarget: Int { profile?.calorieTarget ?? 1800 }
    var caloriesLeft:  Int { max(calorieTarget - caloriesEaten, 0) }
    var protein: Double    { todayLog?.log?.proteinG ?? 0 }
    var carbs: Double      { todayLog?.log?.carbsG ?? 0 }
    var fat: Double        { todayLog?.log?.fatG ?? 0 }
    var proteinTarget: Int { profile?.proteinTargetG ?? 0 }
    var carbsTarget: Int   { profile?.carbsTargetG ?? 0 }
    var fatTarget: Int     { profile?.fatTargetG ?? 0 }
    var streakDays: Int    { todayLog?.log?.streakDay ?? 0 }

    // Goal progress — uses weight log history if available, falls back to profile
    var startWeight: Double  { weightHistory.first?.weightKg ?? profile?.currentWeightKg ?? 0 }
    var currentWeight: Double { weightHistory.last?.weightKg  ?? profile?.currentWeightKg ?? 0 }
    var goalWeight: Double   { profile?.goalWeightKg ?? 0 }

    var goalProgressFraction: Double {
        let total = abs(startWeight - goalWeight)
        guard total > 0 else { return 0 }
        let done = abs(startWeight - currentWeight)
        return min(max(done / total, 0), 1)
    }

    var kgRemaining: Double { max(currentWeight - goalWeight, 0) }

    /// Optimistically remove the entry locally, then tell the server. On
    /// failure we reload from source of truth so state stays consistent.
    func deleteEntry(_ entry: FoodEntry) async {
        let originalLog = todayLog
        // Rebuild the entire struct so @Observable reliably fires and the ring updates immediately.
        if var updated = todayLog {
            updated.entries?.removeAll(where: { $0.id == entry.id })
            if let log = updated.log {
                updated.log = DailyLog(
                    id: log.id,
                    caloriesEaten: max(log.caloriesEaten - entry.calories, 0),
                    proteinG: max(log.proteinG - entry.proteinG, 0),
                    carbsG: max(log.carbsG - entry.carbsG, 0),
                    fatG: max(log.fatG - entry.fatG, 0),
                    onPlan: log.onPlan,
                    streakDay: log.streakDay
                )
            }
            todayLog = updated
            Haptics.impact(.light)
        }
        do {
            try await APIClient.shared.deleteFoodEntry(id: entry.id)
            // Optimistic update already applied above — don't reload here.
            // load() would race the server and could overwrite with stale data.
        } catch {
            todayLog = originalLog
            Haptics.notify(.error)
            print("[Dashboard] delete failed: \(error)")
        }
    }
}

// ── Dashboard View ────────────────────────────────────────────────────────────

struct DashboardView: View {
    @State private var vm = DashboardViewModel()
    @State private var showProfile = false
    @State private var showOnboarding = false
    @State private var showCalorieDetail = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    WLoadingView()
                } else {
                    dashboardContent
                }
            }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "person.circle")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showProfile) {
            NavigationStack { ProfileView() }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingFlowView(onComplete: { showOnboarding = false })
                .onDisappear { Task { await vm.load() } }
        }
        .sheet(isPresented: $showCalorieDetail) {
            CalorieDetailSheet(vm: vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = vm.profile?.name.components(separatedBy: " ").first ?? ""
        let time = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
        return name.isEmpty ? time : "\(time), \(name)"
    }

    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {

                // Profile setup banner — shown when user skipped onboarding
                if vm.profile == nil {
                    Button {
                        showOnboarding = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 24))
                                .foregroundColor(.brandGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set up your profile")
                                    .font(.labelMd)
                                    .foregroundColor(.primary)
                                Text("Get a personalized plan in 2 minutes")
                                    .font(.bodySm)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.textMuted)
                        }
                        .padding(Spacing.md)
                        .background(Color.brandGreenBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .stroke(Color.brandGreen.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showCalorieDetail = true
                    Haptics.impact(.light)
                } label: {
                    WHeroCard {
                        HStack(spacing: Spacing.lg) {
                            WCalorieRing(eaten: vm.caloriesEaten, target: vm.calorieTarget)
                                .frame(width: 100, height: 100)

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(vm.calorieTarget) cal target")
                                        .font(.labelMd)
                                    HStack(spacing: Spacing.md) {
                                        Text("Eaten: \(vm.caloriesEaten)")
                                        Text("Left: \(vm.caloriesLeft)")
                                    }
                                    .font(.bodySm)
                                    .foregroundColor(.textMuted)
                                }
                                HStack(spacing: Spacing.sm) {
                                    Text("P \(Int(vm.protein))/\(vm.proteinTarget)g").font(.bodySm).foregroundColor(.brandPurple)
                                    Text("C \(Int(vm.carbs))/\(vm.carbsTarget)g").font(.bodySm).foregroundColor(.brandGreen)
                                    Text("F \(Int(vm.fat))/\(vm.fatTarget)g").font(.bodySm).foregroundColor(.warning)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Goal progress card
                if vm.goalWeight > 0 && vm.startWeight > vm.goalWeight {
                    goalProgressCard
                }

                // Coach message
                if let msg = vm.coachMessage {
                    WCoachBubble(message: msg.message)
                }

                // Streak badge
                if vm.streakDays > 0 {
                    HStack {
                        Image(systemName: "flame.fill").foregroundColor(.warning)
                        Text("\(vm.streakDays) day streak — keep it up!")
                            .font(.labelSm)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.warning.opacity(0.1))
                    .clipShape(Capsule())
                }

                // Today’s food log — grouped by meal type
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    WSectionHeader(
                        eyebrow: "Today",
                        title: "Food log",
                        subtitle: "Long-press any entry to remove it."
                    )

                    if let entries = vm.todayLog?.entries, !entries.isEmpty {
                        ForEach(groupedEntries(entries), id: \.0) { mealType, mealEntries in
                            mealGroupCard(mealType: mealType, entries: mealEntries)
                        }
                    } else {
                        Text("No food logged yet today")
                            .font(.bodyMd)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(Spacing.lg)
                    }
                }

            }
            .padding(Spacing.md)
        }
        .background(Color.clear)
        .refreshable { await vm.load() }
    }

    private func foodEntryRow(_ entry: FoodEntry) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(mealColor(entry.mealType).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: mealIcon(entry.mealType))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(mealColor(entry.mealType))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName).font(.labelMd)
                Text(entry.mealType.capitalized).font(.bodySm)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            Text("\(entry.calories) cal")
                .font(.labelSm)
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    // ── Goal progress card ───────────────────────────────────────────────
    private var goalProgressCard: some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label("Weight goal", systemImage: "scalemass")
                        .font(.labelSm).foregroundColor(.textMuted)
                    Spacer()
                    Text(String(format: "%.1f kg to go", vm.kgRemaining))
                        .font(.labelSm).foregroundColor(.brandGreen)
                }
                HStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now").font(.bodySm).foregroundColor(.textMuted)
                        Text(String(format: "%.1f kg", vm.currentWeight)).font(.labelMd)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12)).foregroundColor(.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goal").font(.bodySm).foregroundColor(.textMuted)
                        Text(String(format: "%.1f kg", vm.goalWeight))
                            .font(.labelMd).foregroundColor(.brandGreen)
                    }
                    Spacer()
                    Text(String(format: "%.0f%%", vm.goalProgressFraction * 100))
                        .font(.numericMd).foregroundColor(.brandGreen)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.border).frame(height: 6)
                        Capsule().fill(
                            LinearGradient(colors: [.brandGreen, .brandPurple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * vm.goalProgressFraction, height: 6)
                        .animation(.easeOut(duration: 0.6), value: vm.goalProgressFraction)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // ── Grouped food log ─────────────────────────────────────────────────
    private let mealOrder = ["breakfast", "lunch", "snack", "dinner"]

    private func groupedEntries(_ entries: [FoodEntry]) -> [(String, [FoodEntry])] {
        let grouped = Dictionary(grouping: entries) { $0.mealType.lowercased() }
        var result = mealOrder.compactMap { type -> (String, [FoodEntry])? in
            guard let g = grouped[type], !g.isEmpty else { return nil }
            return (type, g)
        }
        // append any meal types not in the standard order
        let known = Set(mealOrder)
        for (type, g) in grouped where !known.contains(type) { result.append((type, g)) }
        return result
    }

    private func mealGroupCard(mealType: String, entries: [FoodEntry]) -> some View {
        let subtotal = entries.reduce(0) { $0 + $1.calories }
        return WCard(padding: 0) {
            VStack(spacing: 0) {
                // Group header
                HStack {
                    Label(mealType.capitalized, systemImage: mealIcon(mealType))
                        .font(.labelSm)
                        .foregroundColor(mealColor(mealType))
                    Spacer()
                    Text("\(subtotal) cal")
                        .font(.labelSm).foregroundColor(.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                Divider()

                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    foodEntryRow(entry)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await vm.deleteEntry(entry) }
                            } label: {
                                Label("Delete entry", systemImage: "trash")
                            }
                        }
                    if i < entries.count - 1 {
                        Divider().padding(.leading, Spacing.md)
                    }
                }
            }
        }
    }

    private func mealIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "breakfast": return "sunrise.fill"
        case "lunch":     return "sun.max.fill"
        case "snack":     return "leaf.fill"
        case "dinner":    return "moon.stars.fill"
        default:          return "fork.knife"
        }
    }

    private func mealColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "breakfast": return .warning
        case "lunch":     return .brandGreen
        case "snack":     return .brandPurple
        case "dinner":    return .infoText
        default:          return .textMuted
        }
    }
}

// ── Calorie detail sheet ─────────────────────────────────────────────────────
// Tapped from the Home hero card — gives a full breakdown of today's totals
// plus the list of entries that add up to the "Eaten" number.

struct CalorieDetailSheet: View {
    let vm: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Big ring up top
                    WCalorieRing(eaten: vm.caloriesEaten, target: vm.calorieTarget)
                        .frame(width: 180, height: 180)
                        .padding(.top, Spacing.lg)

                    // Three-up numbers
                    HStack(spacing: Spacing.sm) {
                        WStatCard(value: "\(vm.calorieTarget)", label: "Target", valueColor: .primary)
                        WStatCard(value: "\(vm.caloriesEaten)", label: "Eaten",  valueColor: .brandGreen)
                        WStatCard(
                            value: "\(vm.caloriesLeft)",
                            label: vm.caloriesEaten > vm.calorieTarget ? "Over" : "Left",
                            valueColor: vm.caloriesEaten > vm.calorieTarget ? .danger : .brandPurple
                        )
                    }
                    .padding(.horizontal, Spacing.md)

                    // Macros
                    WCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack {
                                Text("Macros").font(.labelMd)
                                Spacer()
                                Text("\(vm.calorieTarget) cal = \(vm.proteinTarget)g P · \(vm.carbsTarget)g C · \(vm.fatTarget)g F")
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                            }
                            WMacroRow(
                                protein: vm.protein, proteinTarget: Double(vm.proteinTarget),
                                carbs: vm.carbs, carbsTarget: Double(vm.carbsTarget),
                                fat: vm.fat, fatTarget: Double(vm.fatTarget)
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)

                    // Entries list
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("What you logged")
                            .font(.labelMd)
                            .padding(.horizontal, Spacing.md)

                        if let entries = vm.todayLog?.entries, !entries.isEmpty {
                            WCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.foodName).font(.labelMd)
                                                Text(entry.mealType.capitalized)
                                                    .font(.bodySm)
                                                    .foregroundColor(.textMuted)
                                            }
                                            Spacer()
                                            Text("\(entry.calories) cal")
                                                .font(.labelSm)
                                                .foregroundColor(.textMuted)
                                        }
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        if i < entries.count - 1 {
                                            Divider().padding(.leading, Spacing.md)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        } else {
                            Text("Nothing logged yet today.")
                                .font(.bodyMd)
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, Spacing.lg)
                        }
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.appBackground)
            .navigationTitle("Today's calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// ── Profile View (settings) ───────────────────────────────────────────────────

struct ProfileView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showEditProfile    = false
    @State private var showNotifications  = false

    var body: some View {
        List {
            if let profile {
                Section {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.brandGreenBg)
                                .frame(width: 56, height: 56)
                            Text(profile.name.prefix(1).uppercased())
                                .font(.numericMd)
                                .foregroundColor(.brandGreen)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.titleSm)
                            Text("\(profile.calorieTarget) cal / day target")
                                .font(.bodySm)
                                .foregroundColor(.textMuted)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }

            Section("Account") {
                Button { showEditProfile = true } label: {
                    Label("Edit Profile", systemImage: "gearshape")
                        .foregroundColor(.primary)
                }
                Button { showNotifications = true } label: {
                    Label("Notifications", systemImage: "bell")
                        .foregroundColor(.primary)
                }
                Button {
                    if let url = URL(string: "https://stride-backend-zyytfut7bq-uc.a.run.app/privacy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                        .foregroundColor(.primary)
                }
            }

            Section {
                Button(role: .destructive) {
                    Haptics.notify(.warning)
                    appState.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    Haptics.notify(.warning)
                    showDeleteConfirm = true
                } label: {
                    if isDeletingAccount {
                        HStack(spacing: Spacing.sm) {
                            ProgressView().tint(.danger)
                            Text("Deleting account…")
                        }
                    } else {
                        Label("Delete account", systemImage: "trash")
                    }
                }
                .disabled(isDeletingAccount)
            }

            if let err = deleteError {
                Section {
                    Text(err)
                        .font(.bodySm)
                        .foregroundColor(.danger)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
                .onDisappear { Task { profile = try? await APIClient.shared.getProfile() } }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSettingsView()
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete my account", role: .destructive) {
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all your data — logs, meal plans, and progress. This cannot be undone.")
        }
        .task {
            profile = try? await APIClient.shared.getProfile()
        }
    }

    private func performDeleteAccount() async {
        isDeletingAccount = true
        deleteError = nil
        do {
            try await APIClient.shared.deleteAccount()
            Haptics.notify(.success)
            appState.signOut()
        } catch {
            deleteError = error.localizedDescription
            Haptics.notify(.error)
        }
        isDeletingAccount = false
    }
}
