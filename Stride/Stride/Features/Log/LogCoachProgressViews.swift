import SwiftUI
import Charts

// ── Log Food View ─────────────────────────────────────────────────────────────

@Observable
@MainActor

class LogFoodViewModel {
    var foodName: String = ""
    // Optional so a fresh field renders empty (placeholder) instead of "0".
    var calories: Int? = nil
    var proteinG: Double? = nil
    var carbsG: Double? = nil
    var fatG: Double? = nil
    var mealType: String = "lunch"
    var servingSize: String = "1 serving"
    var logMethod: String = "manual"
    var isLogging = false
    var successMessage: String?
    var error: String?

    var isValid: Bool { !foodName.isEmpty && (calories ?? 0) > 0 }

    func logFood() async -> Bool {
        guard isValid else { return false }
        isLogging = true
        error = nil
        let entry = FoodEntry(
            mealType: mealType, foodName: foodName,
            calories: calories ?? 0,
            proteinG: proteinG ?? 0,
            carbsG: carbsG ?? 0,
            fatG: fatG ?? 0,
            servingSize: servingSize, logMethod: logMethod
        )
        defer { isLogging = false }
        do {
            let res = try await APIClient.shared.logFood(entry)
            Haptics.notify(.success)
            successMessage = "Logged! Total today: \(res.totalCalories) cal"
            reset()
            return true
        } catch {
            Haptics.notify(.error)
            self.error = error.localizedDescription
            return false
        }
    }

    func reset() {
        foodName = ""
        calories = nil; proteinG = nil; carbsG = nil; fatG = nil
        servingSize = "1 serving"
    }
}

struct LogFoodView: View {
    @State private var vm = LogFoodViewModel()
    @State private var showComingSoon = false
    @State private var comingSoonTitle = ""
    @FocusState private var focusedField: Field?

    /// Called after a successful log. Parent (MainTabView) switches to Home
    /// so the user immediately sees the updated totals.
    var onLogged: (() -> Void)? = nil

    let mealTypes = ["breakfast", "lunch", "snack", "dinner"]

    enum Field: Hashable { case foodName, calories, serving, protein, carbs, fat }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {

                    // Log method
                    HStack(spacing: Spacing.sm) {
                        logMethodButton(icon: "barcode.viewfinder", label: "Scan",   method: "barcode")
                        logMethodButton(icon: "camera.fill",         label: "Photo",  method: "photo")
                        logMethodButton(icon: "list.bullet",         label: "Manual", method: "manual")
                    }

                    // Manual entry form
                    if vm.logMethod == "manual" {
                        WCard {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                formField("Food name") {
                                    TextField("e.g. Chicken rice bowl", text: $vm.foodName)
                                        .focused($focusedField, equals: .foodName)
                                }
                                formField("Meal type") {
                                    Picker("", selection: $vm.mealType) {
                                        ForEach(mealTypes, id: \.self) {
                                            Text($0.capitalized).tag($0)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                HStack(spacing: Spacing.md) {
                                    formField("Calories") {
                                        TextField("e.g. 450", value: $vm.calories, format: .number)
                                            .keyboardType(.numberPad)
                                            .focused($focusedField, equals: .calories)
                                    }
                                    formField("Serving") {
                                        TextField("1 serving", text: $vm.servingSize)
                                            .focused($focusedField, equals: .serving)
                                    }
                                }
                                HStack(spacing: Spacing.md) {
                                    formField("Protein (g)") {
                                        TextField("0", value: $vm.proteinG, format: .number)
                                            .keyboardType(.decimalPad)
                                            .focused($focusedField, equals: .protein)
                                    }
                                    formField("Carbs (g)") {
                                        TextField("0", value: $vm.carbsG, format: .number)
                                            .keyboardType(.decimalPad)
                                            .focused($focusedField, equals: .carbs)
                                    }
                                    formField("Fat (g)") {
                                        TextField("0", value: $vm.fatG, format: .number)
                                            .keyboardType(.decimalPad)
                                            .focused($focusedField, equals: .fat)
                                    }
                                }
                            }
                        }
                    } else if vm.logMethod == "barcode" {
                        barcodePlaceholder
                    } else {
                        photoPlaceholder
                    }

                    if let msg = vm.successMessage {
                        Text(msg).font(.bodyMd).foregroundColor(.success)
                            .padding(Spacing.md)
                            .background(Color.brandGreenBg)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }

                    if let err = vm.error {
                        Text(err).font(.bodySm).foregroundColor(.danger)
                    }

                    WButton(title: "Log food", isLoading: vm.isLogging) {
                        Task {
                            focusedField = nil
                            let ok = await vm.logFood()
                            if ok { onLogged?() }
                        }
                    }
                    .disabled(!vm.isValid)
                    .opacity(vm.isValid ? 1 : 0.5)
                }
                .padding(Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Log food")
            .background(Color.appBackground)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .alert(comingSoonTitle, isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { vm.logMethod = "manual" }
        } message: {
            Text("This feature is coming soon. Use manual entry for now.")
        }
    }

    private func logMethodButton(icon: String, label: String, method: String) -> some View {
        let selected = vm.logMethod == method
        return Button { vm.logMethod = method } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(selected ? .brandGreen : .textMuted)
                Text(label).font(.labelSm)
                    .foregroundColor(selected ? .brandGreen : .textMuted)
            }
            .frame(maxWidth: .infinity)
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

    private var barcodePlaceholder: some View {
        WCard {
            VStack(spacing: Spacing.md) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(.textMuted)
                Text("Tap to open camera and scan a barcode")
                    .font(.bodyMd)
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
                WButton(title: "Open scanner") {
                    comingSoonTitle = "Barcode Scanner"
                    showComingSoon = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
        }
    }

    private var photoPlaceholder: some View {
        WCard {
            VStack(spacing: Spacing.md) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.textMuted)
                Text("Take a photo and AI will estimate the calories")
                    .font(.bodyMd)
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
                WButton(title: "Open camera") {
                    comingSoonTitle = "Photo Food Recognition"
                    showComingSoon = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
        }
    }

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(.labelSm).foregroundColor(.textMuted)
            content()
                .padding(Spacing.sm)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// ── Coach View ────────────────────────────────────────────────────────────────

struct CoachView: View {
    @State private var message: CoachMessage?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    WLoadingView(message: "Loading your coach...")
                } else if let msg = message {
                    coachContent(msg)
                } else {
                    emptyCoachView
                }
            }
            .navigationTitle("Your coach")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            message = try await APIClient.shared.getTodayCoachMessage()
        } catch {
            print("[Coach] \(error)")
        }
        isLoading = false
    }

    private var emptyCoachView: some View {
        WEmptyState(
            icon: "bubble.left.fill",
            title: "No coach message yet",
            subtitle: "Your daily coaching message will appear here each morning.",
            ctaTitle: "Refresh",
            ctaAction: { Task { await load() } }
        )
    }

    private func coachContent(_ msg: CoachMessage) -> some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                WCoachBubble(message: msg.message)

                WCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Label("Today's tip", systemImage: "lightbulb.fill")
                            .font(.labelMd)
                            .foregroundColor(.warning)
                        Text(msg.tip)
                            .font(.bodyMd)
                    }
                }

                if let priorityMeal = msg.priorityMeal {
                    WCard {
                        HStack {
                            Label("Focus on", systemImage: "target")
                                .font(.labelMd)
                            Spacer()
                            Text(priorityMeal.capitalized)
                                .font(.labelMd)
                                .foregroundColor(.brandGreen)
                        }
                    }
                }

                Text("New message arrives every morning at 7am")
                    .font(.bodySm)
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.lg)
            }
            .padding(Spacing.md)
        }
        .background(Color.appBackground)
    }
}

// ── Progress View ─────────────────────────────────────────────────────────────

@Observable
@MainActor

class ProgressViewModel {
    var summary: WeeklySummary?
    var weightHistory: [WeightEntry] = []
    var showingWeightLogger = false
    var newWeight: Double = 80
    var isLoading = true
    var error: String?

    func load() async {
        isLoading = true
        error = nil

        // Load each independently so one failure doesn't break the screen
        do { summary = try await APIClient.shared.getWeeklySummary() }
        catch { print("[Progress] summary: \(error)") }

        do {
            weightHistory = try await APIClient.shared.getWeightHistory()
            weightHistory.sort { $0.loggedAtDate < $1.loggedAtDate }
        }
        catch { print("[Progress] weightHistory: \(error)") }

        isLoading = false
    }

    func logWeight() async {
        do {
            try await APIClient.shared.logWeight(newWeight)
            Haptics.notify(.success)
            showingWeightLogger = false
            await load()
        } catch {
            Haptics.notify(.error)
            self.error = error.localizedDescription
        }
    }

    /// Change from the first logged weight to the most recent, in kg.
    /// Positive = gained, negative = lost. `nil` until we have ≥2 data points.
    var weightDelta: Double? {
        guard let first = weightHistory.first?.weightKg,
              let last  = weightHistory.last?.weightKg,
              weightHistory.count >= 2
        else { return nil }
        return last - first
    }
}

struct ProgressTrackingView: View {
    @State private var vm = ProgressViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    WLoadingView()
                } else {
                    progressContent
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showingWeightLogger = true
                    } label: {
                        Image(systemName: "scalemass")
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showingWeightLogger) {
            weightLogSheet
                .presentationDetents([.height(260)])
        }
    }

    private var progressContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Weekly stats grid
                if let s = vm.summary {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                        WStatCard(value: "\(s.daysOnPlan)/\(s.daysLogged)", label: "Days on plan")
                        WStatCard(value: "\(s.avgCalories)", label: "Avg cal/day")
                        WStatCard(value: "\(Int(s.avgProteinG))g", label: "Avg protein")
                        WStatCard(value: "\(s.bestStreak)", label: "Best streak")
                    }
                }

                // Weight history
                if !vm.weightHistory.isEmpty {
                    WCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Weight")
                                        .font(.labelSm)
                                        .foregroundColor(.textMuted)
                                    if let latest = vm.weightHistory.last {
                                        Text(String(format: "%.1f kg", latest.weightKg))
                                            .font(.numericMd)
                                    }
                                }
                                Spacer()
                                if let delta = vm.weightDelta {
                                    weightDeltaBadge(delta)
                                }
                            }
                            weightChart
                        }
                    }
                } else {
                    WCard {
                        WEmptyState(
                            icon: "scalemass",
                            title: "No weight logged yet",
                            subtitle: "Tap the scale icon to log your first weight.",
                            ctaTitle: "Log weight",
                            ctaAction: { vm.showingWeightLogger = true }
                        )
                        .frame(minHeight: 200)
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(Color.appBackground)
        .refreshable { await vm.load() }
    }

    private func weightDeltaBadge(_ delta: Double) -> some View {
        let isLoss = delta <= 0
        let color: Color = isLoss ? .success : .warning
        let iconName = isLoss ? "arrow.down.right" : "arrow.up.right"
        return HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
            Text(String(format: "%@%.1f kg", isLoss ? "" : "+", delta))
                .font(.labelSm)
        }
        .foregroundColor(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var weightChart: some View {
        let entries = vm.weightHistory
        let weights = entries.map(\.weightKg)
        let minW = (weights.min() ?? 0) - 1
        let maxW = (weights.max() ?? 1) + 1

        return Chart {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                LineMark(
                    x: .value("Day", index),
                    y: .value("Weight", entry.weightKg)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.brandGreen, .brandPurple],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Day", index),
                    y: .value("Weight", entry.weightKg)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.brandGreen.opacity(0.25), Color.brandGreen.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Day", index),
                    y: .value("Weight", entry.weightKg)
                )
                .foregroundStyle(Color.brandGreen)
                .symbolSize(28)
            }
        }
        .chartYScale(domain: minW...maxW)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Color.border.opacity(0.5))
                AxisValueLabel().font(.bodySm).foregroundStyle(Color.textMuted)
            }
        }
        .frame(height: 160)
    }

    private var weightLogSheet: some View {
        VStack(spacing: Spacing.lg) {
            Text("Log your weight")
                .font(.titleSm)
            HStack {
                Text("Weight (kg)")
                    .font(.bodyMd)
                Spacer()
                Stepper(String(format: "%.1f kg", vm.newWeight),
                        value: $vm.newWeight, in: 30...300, step: 0.1)
            }
            .padding(Spacing.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            WButton(title: "Save") { Task { await vm.logWeight() } }
        }
        .padding(Spacing.lg)
    }
}
