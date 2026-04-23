import SwiftUI

// ── Main tab bar ──────────────────────────────────────────────────────────────

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Home",     systemImage: "house.fill") }
                .tag(0)

            MealPlanView()
                .tabItem { Label("Meals",    systemImage: "fork.knife") }
                .tag(1)

            LogFoodView()
                .tabItem { Label("Log",      systemImage: "plus.circle.fill") }
                .tag(2)

            CoachView()
                .tabItem { Label("Coach",    systemImage: "bubble.left.fill") }
                .tag(3)

            ProgressView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(4)
        }
        .tint(Color.brandGreen)
    }
}

// ── Dashboard ViewModel ───────────────────────────────────────────────────────

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var todayLog: TodayLogResponse?
    @Published var coachMessage: CoachMessage?
    @Published var profile: UserProfile?
    @Published var isLoading = true
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        async let logTask     = APIClient.shared.getTodayLog()
        async let coachTask   = APIClient.shared.getTodayCoachMessage()
        async let profileTask = APIClient.shared.getProfile()

        do {
            let (log, coach, prof) = try await (logTask, coachTask, profileTask)
            todayLog = log
            coachMessage = coach
            profile = prof
        } catch {
            self.error = error.localizedDescription
        }
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
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    WLoadingView()
                } else if let error = vm.error {
                    WErrorView(message: error) { Task { await vm.load() } }
                } else {
                    dashboardContent
                }
            }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.circle")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .task { await vm.load() }
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
    @EnvironmentObject var appState: AppState

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
