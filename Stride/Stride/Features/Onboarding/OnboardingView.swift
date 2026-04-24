import SwiftUI

// ── Onboarding ViewModel ──────────────────────────────────────────────────────

@Observable
@MainActor

class OnboardingViewModel {
    // Form state
    var goal: String = "lose_weight"
    var name: String = ""
    var age: Int = 30
    var gender: String = "male"
    var heightCm: Int = 175
    var currentWeight: Double = 80
    var goalWeight: Double = 70
    var timelineMonths: Int = 6
    var activityLevel: String = "light"
    var dailyMinutes: Int = 15
    var dietPrefs: Set<String> = []

    // Navigation
    var currentStep: Int = 0
    let totalSteps = 5

    // AI result
    var plan: OnboardingPlanResponse?
    var isGenerating = false
    var error: String?

    func toggleDietPref(_ pref: String) {
        if pref == "none" {
            dietPrefs = []
        } else {
            dietPrefs.remove("none")
            if dietPrefs.contains(pref) {
                dietPrefs.remove(pref)
            } else {
                dietPrefs.insert(pref)
            }
        }
    }

    func next() {
        if currentStep < totalSteps - 1 {
            withAnimation { currentStep += 1 }
        }
    }

    var buildProfile: UserProfile {
        UserProfile(
            name: name, age: age, gender: gender,
            heightCm: heightCm, currentWeightKg: currentWeight,
            goalWeightKg: goalWeight, timelineMonths: timelineMonths,
            activityLevel: activityLevel, dailyMinutes: dailyMinutes,
            dietPrefs: Array(dietPrefs), primaryGoal: goal,
            calorieTarget: 0, proteinTargetG: 0, carbsTargetG: 0, fatTargetG: 0
        )
    }

    func generatePlan() async {
        isGenerating = true
        error = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = 3
        }

        do {
            plan = try await APIClient.shared.completeOnboarding(profile: buildProfile)
            withAnimation { currentStep = 4 } // jump to result screen
        } catch {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentStep = 2
            }
            print("[Onboarding] generatePlan failed: \(error)")
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            self.error = message.isEmpty
                ? "Could not generate your plan right now. You can retry or skip and set up later."
                : message
        }
        isGenerating = false
    }
}

// ── Onboarding flow container ─────────────────────────────────────────────────

struct OnboardingFlowView: View {
    @Environment(AppState.self) var appState
    @State private var vm = OnboardingViewModel()
    var onComplete: (() -> Void)? = nil

    var body: some View {
        WScreenBackground {
            VStack(spacing: 0) {
                VStack(spacing: Spacing.md) {
                    HStack {
                        Text("Step \(min(vm.currentStep + 1, vm.totalSteps)) of \(vm.totalSteps)")
                            .font(.labelSm)
                            .foregroundColor(.textMuted)
                        Spacer()
                        if vm.currentStep < vm.totalSteps - 1 {
                            Text(progressLabel)
                                .font(.labelSm)
                                .foregroundColor(.brandGreen)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.45))
                                .frame(height: 8)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.brandGreen, Color.brandPurple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * CGFloat(vm.currentStep + 1) / CGFloat(vm.totalSteps),
                                    height: 8
                                )
                                .animation(.easeInOut, value: vm.currentStep)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)

                TabView(selection: $vm.currentStep) {
                    OnboardingGoalScreen(vm: vm).tag(0)
                    OnboardingBodyScreen(vm: vm).tag(1)
                    OnboardingLifestyleScreen(vm: vm) {
                        onComplete?() ?? appState.completeOnboarding()
                    }.tag(2)
                    OnboardingGeneratingScreen(vm: vm).tag(3)
                    OnboardingResultScreen(vm: vm) {
                        onComplete?() ?? appState.completeOnboarding()
                    }.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: vm.currentStep)
                .onChange(of: vm.currentStep) { _, _ in dismissKeyboard() }
            }
        }
    }

    /// Drops first responder so the keyboard doesn't linger when the user
    /// moves past a step that had a focused text field.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private var progressLabel: String {
        switch vm.currentStep {
        case 0: return "Goal"
        case 1: return "Body"
        case 2: return "Lifestyle"
        case 3: return "Generating"
        default: return "Ready"
        }
    }
}

// ── Screen 1: Goal ────────────────────────────────────────────────────────────

struct OnboardingGoalScreen: View {
    @Bindable var vm: OnboardingViewModel

    let goals = [
        ("lose_weight",    "Lose weight",    "Reach my goal weight",      "scalemass"),
        ("eat_healthier",  "Eat healthier",  "Better daily habits",       "fork.knife"),
        ("more_energy",    "More energy",    "Feel better every day",     "bolt.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            WSectionHeader(
                eyebrow: "Goal",
                title: "What's your main goal?",
                subtitle: "We'll shape the entire Stride experience around the outcome you care about most."
            )

            WHeroCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personalized from day one")
                            .font(.labelMd)
                        Text("Meal guidance, coach tone, and calorie targets adapt to what you pick here.")
                            .font(.bodySm)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.brandPurple)
                }
            }

            VStack(spacing: Spacing.sm) {
                ForEach(goals, id: \.0) { id, title, subtitle, icon in
                    goalCard(id: id, title: title, subtitle: subtitle, icon: icon)
                }
            }

            Spacer()
            WButton(title: "Continue") { vm.next() }
        }
        .padding(Spacing.lg)
    }

    private func goalCard(id: String, title: String, subtitle: String, icon: String) -> some View {
        let selected = vm.goal == id
        return Button {
            Haptics.selection()
            vm.goal = id
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(selected ? .brandGreen : .textMuted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.labelMd)
                    Text(subtitle).font(.bodySm).foregroundColor(.textMuted)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.brandGreen)
                }
            }
            .padding(Spacing.md)
            .background(selected ? Color.brandGreenBg : Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(selected ? Color.brandGreen : Color.border, lineWidth: selected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }
}

// ── Screen 2: Body stats ──────────────────────────────────────────────────────

struct OnboardingBodyScreen: View {
    @Bindable var vm: OnboardingViewModel
    @State private var heightText = ""
    @State private var currentWeightText = ""
    @State private var goalWeightText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                WSectionHeader(
                    eyebrow: "Profile",
                    title: "Your body stats",
                    subtitle: "These details let Stride build realistic calorie and weight targets instead of generic defaults."
                )

                WHeroCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Quick profile")
                            .font(.labelMd)
                        Text("Keep this practical. You can always refine your targets later in the app.")
                            .font(.bodySm)
                            .foregroundColor(.textMuted)
                    }
                }

                WCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        formField("Your name") {
                            TextField("e.g. Ravi", text: $vm.name)
                                .textContentType(.givenName)
                        }

                        HStack(spacing: Spacing.md) {
                            formField("Age") {
                                Stepper("\(vm.age)", value: $vm.age, in: 13...80)
                            }
                            formField("Gender") {
                                Picker("", selection: $vm.gender) {
                                    Text("Male").tag("male")
                                    Text("Female").tag("female")
                                    Text("Other").tag("other")
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        HStack(spacing: Spacing.md) {
                            formField("Height (cm)") {
                                TextField("175", text: $heightText)
                                    .keyboardType(.numberPad)
                                    .onChange(of: heightText) { _, new in
                                        if let v = Int(new), (100...220).contains(v) { vm.heightCm = v }
                                    }
                            }
                            formField("Weight (kg)") {
                                TextField("80.0", text: $currentWeightText)
                                    .keyboardType(.decimalPad)
                                    .onChange(of: currentWeightText) { _, new in
                                        if let v = Double(new), (30...300).contains(v) { vm.currentWeight = v }
                                    }
                            }
                        }

                        formField("Goal weight (kg)") {
                            TextField("70.0", text: $goalWeightText)
                                .keyboardType(.decimalPad)
                                .onChange(of: goalWeightText) { _, new in
                                    if let v = Double(new), (30...300).contains(v) { vm.goalWeight = v }
                                }
                        }

                        formField("Timeline") {
                            HStack(spacing: Spacing.sm) {
                                ForEach([3, 6, 12], id: \.self) { months in
                                    WChip(
                                        label: "\(months) mo",
                                        isSelected: vm.timelineMonths == months
                                    ) { vm.timelineMonths = months }
                                }
                            }
                        }
                    }
                }

                WButton(title: "Continue") { vm.next() }
                    .padding(.top, Spacing.sm)
            }
            .padding(Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if heightText.isEmpty { heightText = "\(vm.heightCm)" }
            if currentWeightText.isEmpty { currentWeightText = String(format: "%.1f", vm.currentWeight) }
            if goalWeightText.isEmpty { goalWeightText = String(format: "%.1f", vm.goalWeight) }
        }
    }

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.labelSm)
                .foregroundColor(.textMuted)
            content()
                .padding(Spacing.md)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
    }
}

// ── Screen 3: Lifestyle ───────────────────────────────────────────────────────

struct OnboardingLifestyleScreen: View {
    @Bindable var vm: OnboardingViewModel
    var onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                WSectionHeader(
                    eyebrow: "Lifestyle",
                    title: "Make the plan fit your week",
                    subtitle: "Stride works best when the recommendations match your time, movement, and food preferences."
                )

                WCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Activity level")
                                .font(.labelSm)
                                .foregroundColor(.textMuted)
                            ForEach([
                                ("sedentary", "Mostly sitting", "Desk job, little walking"),
                                ("light",     "Lightly active", "Some walking, light exercise"),
                                ("moderate",  "Moderately active", "Regular exercise 3-4x/week"),
                            ], id: \.0) { id, title, sub in
                                Button {
                                    Haptics.selection()
                                    vm.activityLevel = id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(title).font(.labelMd)
                                            Text(sub).font(.bodySm).foregroundColor(.textMuted)
                                        }
                                        Spacer()
                                        if vm.activityLevel == id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.brandGreen)
                                        }
                                    }
                                    .padding(Spacing.md)
                                    .background(vm.activityLevel == id ? Color.brandGreenBg : Color.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.sm)
                                            .stroke(vm.activityLevel == id ? Color.brandGreen : Color.border,
                                                    lineWidth: vm.activityLevel == id ? 1.5 : 0.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Daily time for health")
                                .font(.labelSm)
                                .foregroundColor(.textMuted)
                            HStack(spacing: Spacing.sm) {
                                ForEach([5, 15, 30], id: \.self) { min in
                                    WChip(label: "\(min) min", isSelected: vm.dailyMinutes == min) {
                                        vm.dailyMinutes = min
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Dietary preferences")
                                .font(.labelSm)
                                .foregroundColor(.textMuted)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                                ForEach(["halal", "vegetarian", "gluten_free", "none"], id: \.self) { pref in
                                    WChip(
                                        label: pref == "gluten_free" ? "Gluten-free" :
                                               pref.prefix(1).uppercased() + pref.dropFirst(),
                                        isSelected: pref == "none" ? vm.dietPrefs.isEmpty : vm.dietPrefs.contains(pref)
                                    ) { vm.toggleDietPref(pref) }
                                }
                            }
                        }
                    }
                }

                WButton(title: vm.error != nil ? "Retry" : "Build my plan", isLoading: vm.isGenerating) {
                    Task { await vm.generatePlan() }
                }

                if let error = vm.error {
                    Text(error)
                        .font(.bodySm)
                        .foregroundColor(.danger)
                        .multilineTextAlignment(.center)

                    WButtonOutline(title: "Skip for now") { onSkip() }
                }
            }
            .padding(Spacing.lg)
        }
    }
}

// ── Screen 4: Generating ──────────────────────────────────────────────────────

struct OnboardingGeneratingScreen: View {
    @Bindable var vm: OnboardingViewModel
    @State private var completedSteps = 0

    let steps = [
        "Calculating your calorie target",
        "Creating your weight loss schedule",
        "Writing your coach message",
        "Building your meal suggestions",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            WSectionHeader(
                eyebrow: "Generating",
                title: "Building your plan",
                subtitle: "This should only take a moment. We’re turning your inputs into a usable starting plan."
            )

            WHeroCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        let isDone    = vm.plan != nil || i < completedSteps
                        let isCurrent = vm.plan == nil && i == completedSteps
                        HStack(spacing: Spacing.md) {
                            if isDone {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.success)
                                    .transition(.scale.combined(with: .opacity))
                            } else if isCurrent {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 20, height: 20)
                            } else {
                                Circle()
                                    .stroke(Color.border, lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                            }
                            Text(step)
                                .font(.bodyMd)
                                .foregroundColor(isDone || isCurrent ? .primary : .textMuted)
                                .animation(.easeInOut, value: isDone)
                        }
                    }
                }
            }

            if let plan = vm.plan {
                HStack(spacing: Spacing.md) {
                    WStatCard(value: "\(plan.calorieTarget)", label: "cal / day",
                              valueColor: .brandGreen)
                    WStatCard(value: plan.goalDate, label: "goal reached")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(Spacing.lg)
        .task {
            // Advance one step every 5s, leaving the last step to spin until
            // the API responds. If the plan arrives first, everything jumps to done.
            for i in 0..<(steps.count - 1) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard vm.plan == nil else { break }
                withAnimation(.easeInOut(duration: 0.4)) { completedSteps = i + 1 }
            }
        }
    }
}

// ── Screen 5: Result ──────────────────────────────────────────────────────────

struct OnboardingResultScreen: View {
    @Bindable var vm: OnboardingViewModel
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            WSectionHeader(
                eyebrow: "Ready",
                title: "Meet your coach",
                subtitle: "Your first plan is ready. You can start with this immediately and adjust it over time."
            )

            if let plan = vm.plan {
                WHeroCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        WCoachBubble(message: plan.coachMessage)
                        HStack(spacing: Spacing.md) {
                            WStatCard(value: "\(plan.calorieTarget)", label: "daily cal", valueColor: .brandGreen)
                            WStatCard(value: String(format: "%.1f", plan.weeklyLossKg), label: "kg / week", valueColor: .brandPurple)
                        }
                    }
                }

                VStack(spacing: Spacing.sm) {
                    resultRow(
                        icon: "chart.line.downtrend.xyaxis",
                        title: "Weight loss plan",
                        detail: plan.planSummary
                    )
                    resultRow(
                        icon: "flame.fill",
                        title: "Daily calorie target",
                        detail: "\(plan.calorieTarget) cal / day"
                    )
                    resultRow(
                        icon: "calendar",
                        title: "Goal date",
                        detail: plan.goalDate
                    )
                }
            }

            Spacer()
            WButton(title: "Go to my dashboard", action: onComplete)
        }
        .padding(Spacing.lg)
    }

    private func resultRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.brandGreen)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.labelSm).foregroundColor(.textMuted)
                Text(detail).font(.labelMd)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.success)
        }
        .padding(Spacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}
