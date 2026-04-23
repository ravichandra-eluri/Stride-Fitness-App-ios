import SwiftUI
import Combine

// ── Meal Plan ViewModel ───────────────────────────────────────────────────────

@Observable
@MainActor

class MealPlanViewModel {
    var plan: WeeklyMealPlan?
    var selectedDay: String = ""
    var isLoading = true
    var isRegenerating = false
    var swapTargetMeal: Meal?
    var swapAlternatives: [Meal] = []
    var isSwapping = false
    var selectedFilter = "similar_calories"
    var error: String?
    var noProfile = false
    var swapSelectionKey: String?

    var currentDayPlan: DayPlan? {
        plan?.days.first { $0.day == selectedDay }
    }

    func load() async {
        isLoading = true
        error = nil
        noProfile = false
        do {
            plan = try await APIClient.shared.getMealPlan()
            selectedDay = plan?.days.first?.day ?? ""
        } catch let apiError as APIError {
            if case .serverError(404, let msg) = apiError {
                if msg.contains("profile not found") {
                    noProfile = true
                } else {
                    plan = nil  // no plan yet — new user with profile
                }
            } else {
                self.error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func regenerate() async {
        isRegenerating = true
        error = nil
        do {
            plan = try await APIClient.shared.regenerateMealPlan()
            selectedDay = plan?.days.first?.day ?? ""
        } catch let apiError as APIError {
            if case .serverError(404, let msg) = apiError, msg.contains("profile not found") {
                noProfile = true
            } else {
                self.error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
        isRegenerating = false
    }

    func loadSwapAlternatives(for meal: Meal) async {
        swapTargetMeal = meal
        isSwapping = true
        swapAlternatives = []
        swapSelectionKey = nil
        do {
            let res = try await APIClient.shared.swapMeal(
                mealPlanID: "", day: selectedDay,
                meal: meal, filter: selectedFilter
            )
            swapAlternatives = res.alternatives
        } catch {
            self.error = error.localizedDescription
        }
        isSwapping = false
    }

    func confirmSwap(with newMeal: Meal) {
        guard let target = swapTargetMeal,
              let dayIndex = plan?.days.firstIndex(where: { $0.day == selectedDay }),
              let mealIndex = plan?.days[dayIndex].meals.firstIndex(where: { $0.name == target.name })
        else { return }

        var days = plan!.days
        var meals = days[dayIndex].meals
        meals[mealIndex] = newMeal
        let newTotal = meals.reduce(0) { $0 + $1.calories }
        days[dayIndex] = DayPlan(day: days[dayIndex].day, meals: meals, totalCalories: newTotal)
        plan = WeeklyMealPlan(week: plan!.week, days: days, avgDailyCalories: plan!.avgDailyCalories)
        swapTargetMeal = nil
        swapAlternatives = []
        swapSelectionKey = nil
        Haptics.notify(.success)
    }
}

// ── Meal Plan View ────────────────────────────────────────────────────────────

struct MealPlanView: View {
    @State private var vm = MealPlanViewModel()
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    WLoadingView(message: "Loading your meal plan...")
                } else if vm.isRegenerating {
                    // Generating a plan takes 30–90s of Claude time. Show a
                    // richer placeholder so the user knows what's happening.
                    GeneratingMealPlanView()
                } else if let error = vm.error {
                    WErrorView(message: error) { Task { await vm.regenerate() } }
                } else if vm.noProfile {
                    noProfileView
                } else if vm.plan != nil {
                    mealPlanContent
                } else {
                    emptyMealPlanView
                }
            }
            .navigationTitle("Meal plan")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await vm.load() }
        .sheet(isPresented: $showOnboarding) {
            OnboardingFlowView(onComplete: { showOnboarding = false })
                .onDisappear { Task { await vm.load() } }
        }
        .sheet(isPresented: .init(
            get: { vm.swapTargetMeal != nil },
            set: {
                if !$0 {
                    vm.swapTargetMeal = nil
                    vm.swapAlternatives = []
                    vm.swapSelectionKey = nil
                }
            }
        )) {
            MealSwapSheet(vm: vm)
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
    }

    private var noProfileView: some View {
        WEmptyState(
            icon: "person.crop.circle.badge.exclamationmark",
            title: "Profile not set up",
            subtitle: "Complete your profile so we can generate a personalized meal plan for you.",
            ctaTitle: "Set up my profile",
            ctaAction: { showOnboarding = true }
        )
    }

    private var mealPlanContent: some View {
        VStack(spacing: 0) {
            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(vm.plan?.days ?? []) { day in
                        WChip(
                            label: String(day.day.prefix(3)),
                            isSelected: vm.selectedDay == day.day
                        ) { vm.selectedDay = day.day }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }

            Divider()

            // Meals list
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    if let day = vm.currentDayPlan {
                        WHeroCard {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.day)
                                        .font(.titleMd)
                                    Text("Planned around your current goal")
                                        .font(.bodySm)
                                        .foregroundColor(.textMuted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(day.totalCalories)")
                                        .font(.numericMd)
                                        .foregroundColor(.brandGreen)
                                    Text("cal total")
                                        .font(.bodySm)
                                        .foregroundColor(.textMuted)
                                }
                            }
                        }

                        ForEach(day.meals) { meal in
                            mealCard(meal)
                        }

                        // Daily total
                        HStack {
                            Text("Daily total")
                                .font(.labelMd)
                            Spacer()
                            Text("\(day.totalCalories) cal")
                                .font(.labelMd)
                                .foregroundColor(.brandGreen)
                        }
                        .padding(Spacing.md)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                        // Regenerate button
                        WButtonOutline(title: vm.isRegenerating ? "Regenerating..." : "Regenerate week with AI") {
                            Task { await vm.regenerate() }
                        }
                        .disabled(vm.isRegenerating)
                    }
                }
                .padding(Spacing.md)
            }
        }
        .background(Color.clear)
    }

    private var emptyMealPlanView: some View {
        WEmptyState(
            icon: "fork.knife",
            title: "No meal plan yet",
            subtitle: "Your personalized weekly plan will appear here once it's generated.",
            ctaTitle: vm.isRegenerating ? "Generating..." : "Generate meal plan",
            ctaAction: { Task { await vm.regenerate() } }
        )
    }

    private func mealCard(_ meal: Meal) -> some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(meal.mealType.capitalized, systemImage: mealIcon(meal.mealType))
                            .font(.labelSm)
                            .foregroundColor(mealTint(meal.mealType))
                        Text(meal.name)
                            .font(.labelMd)
                    }
                    Spacer()
                    Button {
                        Task { await vm.loadSwapAlternatives(for: meal) }
                    } label: {
                        Text("Swap")
                            .font(.labelSm)
                            .foregroundColor(.infoText)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.infoText.opacity(0.4), lineWidth: 0.5)
                            )
                    }
                }
                HStack(spacing: Spacing.lg) {
                    Text("\(meal.calories) cal").font(.bodySm).foregroundColor(.textMuted)
                    Text("P \(meal.proteinG)g").font(.bodySm).foregroundColor(.textMuted)
                    Text("C \(meal.carbsG)g").font(.bodySm).foregroundColor(.textMuted)
                    Text("F \(meal.fatG)g").font(.bodySm).foregroundColor(.textMuted)
                    Spacer()
                    Text("\(meal.prepMinutes) min").font(.bodySm).foregroundColor(.textMuted)
                }
            }
        }
    }

    private func mealIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "snack": return "leaf.fill"
        case "dinner": return "moon.stars.fill"
        default: return "fork.knife"
        }
    }

    private func mealTint(_ type: String) -> Color {
        switch type.lowercased() {
        case "breakfast": return .warning
        case "lunch": return .brandGreen
        case "snack": return .brandPurple
        case "dinner": return .infoText
        default: return .textMuted
        }
    }
}

// ── Meal Swap Sheet ───────────────────────────────────────────────────────────

struct MealSwapSheet: View {
    var vm: MealPlanViewModel

    let filters = [
        ("similar_calories", "Similar cal"),
        ("high_protein",     "High protein"),
        ("quick_prep",       "Quick prep"),
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let target = vm.swapTargetMeal {
                    Text("Replacing: \(target.name)")
                        .font(.bodySm)
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, Spacing.md)
                }

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(filters, id: \.0) { id, label in
                            WChip(label: label, isSelected: vm.selectedFilter == id) {
                                vm.selectedFilter = id
                                if let meal = vm.swapTargetMeal {
                                    Task { await vm.loadSwapAlternatives(for: meal) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }

                if vm.isSwapping {
                    WLoadingView(message: "Finding alternatives...")
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.sm) {
                            ForEach(vm.swapAlternatives) { meal in
                                alternativeCard(meal)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }

                Spacer()

                if selectedAlternative != nil {
                    WButton(title: "Confirm swap") {
                        if let meal = selectedAlternative {
                            vm.confirmSwap(with: meal)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
                }
            }
            .padding(.top, Spacing.md)
            .navigationTitle("Swap meal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func alternativeCard(_ meal: Meal) -> some View {
        let isSelected = vm.swapSelectionKey == selectionKey(for: meal)
        return Button {
            vm.swapSelectionKey = selectionKey(for: meal)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name).font(.labelMd)
                    HStack(spacing: Spacing.sm) {
                        Text("\(meal.calories) cal").font(.bodySm)
                        Text("P \(meal.proteinG)g").font(.bodySm)
                        Text("\(meal.prepMinutes) min").font(.bodySm)
                    }
                    .foregroundColor(isSelected ? .infoText : .textMuted)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .brandGreen : .border)
            }
            .padding(Spacing.md)
            .background(isSelected ? Color.brandGreenBg : Color.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isSelected ? Color.brandGreen : Color.border,
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedAlternative: Meal? {
        guard let key = vm.swapSelectionKey else { return nil }
        return vm.swapAlternatives.first { selectionKey(for: $0) == key }
    }

    private func selectionKey(for meal: Meal) -> String {
        "\(meal.name)|\(meal.mealType)|\(meal.calories)"
    }
}

// ── Generating placeholder ───────────────────────────────────────────────────
// Shown while the backend is calling Claude to build a 7-day plan (~30–90s).
// Animates through a checklist so the screen doesn't feel frozen.

struct GeneratingMealPlanView: View {
    @State private var progress: Int = 0

    private let steps: [(String, String)] = [
        ("fork.knife",          "Reading your profile"),
        ("sparkles",            "Asking the AI coach for 7 days of meals"),
        ("chart.bar.doc.horizontal", "Balancing calories and macros"),
        ("checkmark.seal.fill", "Wrapping up your plan")
    ]

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.brandGreenBg)
                        .frame(width: 88, height: 88)
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.brandGreen)
                        .symbolEffect(.pulse, options: .repeating)
                }
                Text("Building your week")
                    .font(.titleSm)
                Text("Stride is generating a 7-day plan around your calorie target and preferences. This usually takes 30–60 seconds.")
                    .font(.bodyMd)
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.md)
            }
            .padding(.top, Spacing.xl)

            WCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: Spacing.md) {
                            stepIcon(isDone: index < progress, isActive: index == progress, icon: step.0)
                            Text(step.1)
                                .font(.bodyMd)
                                .foregroundColor(index <= progress ? .primary : .textMuted)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            // Skeleton meal cards — hints at what's about to appear.
            VStack(spacing: Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in skeletonMealCard }
            }
            .padding(.horizontal, Spacing.md)

            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in
            guard progress < steps.count - 1 else { return }
            withAnimation(.easeInOut) { progress += 1 }
        }
    }

    private func stepIcon(isDone: Bool, isActive: Bool, icon: String) -> some View {
        ZStack {
            Circle()
                .fill(isDone ? Color.brandGreen : Color.surface)
                .frame(width: 28, height: 28)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            } else if isActive {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
        }
    }

    private var skeletonMealCard: some View {
        WCard {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.surface)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surface)
                        .frame(height: 10)
                        .frame(maxWidth: 160)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surface)
                        .frame(height: 8)
                        .frame(maxWidth: 100)
                }
                Spacer()
            }
        }
        .opacity(0.6)
    }
}
