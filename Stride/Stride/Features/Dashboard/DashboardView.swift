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

            LogFoodView()
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
        .onChange(of: selectedTab) { _, _ in Haptics.selection() }
    }
}

// ── Dashboard ViewModel ───────────────────────────────────────────────────────

@Observable
@MainActor

class DashboardViewModel {
    var todayLog: TodayLogResponse?
    var coachMessage: CoachMessage?
    var profile: UserProfile?
    var isLoading = true

    func load() async {
        isLoading = true

        // Load each independently — one failure shouldn't break the whole screen
        do { todayLog = try await APIClient.shared.getTodayLog() }
        catch { print("[Dashboard] todayLog: \(error)") }

        do { coachMessage = try await APIClient.shared.getTodayCoachMessage() }
        catch { print("[Dashboard] coachMessage: \(error)") }

        do { profile = try await APIClient.shared.getProfile() }
        catch { print("[Dashboard] profile: \(error)") }

        isLoading = false
    }

    var caloriesEaten: Int { todayLog?.log?.caloriesEaten ?? 0 }
    var calorieTarget: Int { profile?.calorieTarget ?? 1800 }
    var caloriesLeft:  Int { max(calorieTarget - caloriesEaten, 0) }
    var protein: Double    { todayLog?.log?.proteinG ?? 0 }
    var carbs: Double      { todayLog?.log?.carbsG ?? 0 }
    var fat: Double        { todayLog?.log?.fatG ?? 0 }
    var streakDays: Int    { todayLog?.log?.streakDay ?? 0 }

    /// Optimistically remove the entry locally, then tell the server. On
    /// failure we reload from source of truth so state stays consistent.
    func deleteEntry(_ entry: FoodEntry) async {
        let originalEntries = todayLog?.entries ?? []
        if let idx = todayLog?.entries?.firstIndex(where: { $0.id == entry.id }) {
            todayLog?.entries?.remove(at: idx)
            Haptics.impact(.light)
        }
        do {
            try await APIClient.shared.deleteFoodEntry(id: entry.id)
            await load()
        } catch {
            todayLog?.entries = originalEntries
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
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = vm.profile?.name.components(separatedBy: " ").first ?? ""
        switch hour {
        case 0..<12: return "Good morning\(name.isEmpty ? "" : ", \(name)")"
        case 12..<17: return "Good afternoon\(name.isEmpty ? "" : ", \(name)")"
        default: return "Good evening\(name.isEmpty ? "" : ", \(name)")"
        }
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

                // Calorie ring + macros
                WCard {
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
                            WMacroRow(protein: vm.protein, carbs: vm.carbs, fat: vm.fat)
                        }
                        Spacer()
                    }
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

                // Today's food entries
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Today's food")
                        .font(.titleSm)
                        .padding(.horizontal, Spacing.xs)

                    if let entries = vm.todayLog?.entries, !entries.isEmpty {
                        WCard(padding: 0) {
                            VStack(spacing: 0) {
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
        .background(Color.appBackground)
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

// ── Profile View (settings) ───────────────────────────────────────────────────

struct ProfileView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?

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
                Label("Settings", systemImage: "gearshape")
                Label("Notifications", systemImage: "bell")
                Label("Privacy", systemImage: "hand.raised.fill")
            }

            Section {
                Button(role: .destructive) {
                    Haptics.notify(.warning)
                    appState.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
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
        .task {
            profile = try? await APIClient.shared.getProfile()
        }
    }
}
