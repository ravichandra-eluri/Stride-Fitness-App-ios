import SwiftUI

// ── Main tab bar ──────────────────────────────────────────────────────────────

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AnyView(DashboardView())
                .tabItem { Label("Home",     systemImage: "house.fill") }
                .tag(0)

            AnyView(MealPlanView())
                .tabItem { Label("Meals",    systemImage: "fork.knife") }
                .tag(1)

            AnyView(LogFoodView())
                .tabItem { Label("Log",      systemImage: "plus.circle.fill") }
                .tag(2)

            AnyView(CoachView())
                .tabItem { Label("Coach",    systemImage: "bubble.left.fill") }
                .tag(3)

            AnyView(ProgressTrackingView())
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(4)
        }
        .tint(Color.brandGreen)
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
            AnyView(OnboardingFlowView(onComplete: { showOnboarding = false }))
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
                                ForEach(Array(entries.enumerated()), id: \.offset) { i, entry in
                                    HStack {
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
        .background(Color.surface.opacity(0.4))
        .refreshable { await vm.load() }
    }
}

// ── Profile View (settings) ───────────────────────────────────────────────────

struct ProfileView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            Section("Account") {
                Label("Settings", systemImage: "gearshape")
                Label("Notifications", systemImage: "bell")
            }
            Section {
                Button(role: .destructive) {
                    appState.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
    }
}
