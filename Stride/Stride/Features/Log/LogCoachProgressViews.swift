import SwiftUI

// ── Log Food View ─────────────────────────────────────────────────────────────

@Observable
@MainActor

class LogFoodViewModel {
    var foodName: String = ""
    var calories: Int = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var mealType: String = "lunch"
    var servingSize: String = "1 serving"
    var logMethod: String = "manual"
    var isLogging = false
    var successMessage: String?
    var error: String?

    var isValid: Bool { !foodName.isEmpty && calories > 0 }

    func logFood() async {
        guard isValid else { return }
        isLogging = true
        error = nil
        let entry = FoodEntry(
            mealType: mealType, foodName: foodName,
            calories: calories, proteinG: proteinG,
            carbsG: carbsG, fatG: fatG,
            servingSize: servingSize, logMethod: logMethod
        )
        do {
            let res = try await APIClient.shared.logFood(entry)
            successMessage = "Logged! Total today: \(res.totalCalories) cal"
            reset()
        } catch {
            self.error = error.localizedDescription
        }
        isLogging = false
    }

    func reset() {
        foodName = ""; calories = 0; proteinG = 0; carbsG = 0; fatG = 0
        servingSize = "1 serving"
    }
}

struct LogFoodView: View {
    @State private var vm = LogFoodViewModel()

    let mealTypes = ["breakfast", "lunch", "snack", "dinner"]

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
                                        TextField("0", value: $vm.calories, format: .number)
                                            .keyboardType(.numberPad)
                                    }
                                    formField("Serving") {
                                        TextField("1 serving", text: $vm.servingSize)
                                    }
                                }
                                HStack(spacing: Spacing.md) {
                                    formField("Protein (g)") {
                                        TextField("0", value: $vm.proteinG, format: .number)
                                            .keyboardType(.decimalPad)
                                    }
                                    formField("Carbs (g)") {
                                        TextField("0", value: $vm.carbsG, format: .number)
                                            .keyboardType(.decimalPad)
                                    }
                                    formField("Fat (g)") {
                                        TextField("0", value: $vm.fatG, format: .number)
                                            .keyboardType(.decimalPad)
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
                        Task { await vm.logFood() }
                    }
                    .disabled(!vm.isValid)
                    .opacity(vm.isValid ? 1 : 0.5)
                }
                .padding(Spacing.md)
            }
            .navigationTitle("Log food")
            .background(Color.surface.opacity(0.4))
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
                // In production: integrate AVFoundation barcode scanner here
                WButton(title: "Open scanner") { }
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
                // In production: open camera, send base64 image to Claude vision API
                WButton(title: "Open camera") { }
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
                } else if let error {
                    WErrorView(message: error) { Task { await load() } }
                } else if let msg = message {
                    coachContent(msg)
                } else {
                    WErrorView(message: "No message today yet") { Task { await load() } }
                }
            }
            .navigationTitle("Your coach")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            message = try await APIClient.shared.getTodayCoachMessage()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
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
        .background(Color.surface.opacity(0.4))
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
        async let summaryTask = APIClient.shared.getWeeklySummary()
        async let weightTask  = APIClient.shared.getWeightHistory()
        do {
            let (s, w) = try await (summaryTask, weightTask)
            summary = s
            weightHistory = w
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func logWeight() async {
        do {
            try await APIClient.shared.logWeight(newWeight)
            showingWeightLogger = false
            await load()
        } catch { }
    }
}

struct ProgressView: View {
    @State private var vm = ProgressViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    WLoadingView()
                } else if let error = vm.error {
                    WErrorView(message: error) { Task { await vm.load() } }
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

                // Weight history chart
                if !vm.weightHistory.isEmpty {
                    WCard {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Weight over time")
                                .font(.labelMd)
                            weightChart
                        }
                    }
                } else {
                    WCard {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "scalemass")
                                .font(.system(size: 32))
                                .foregroundColor(.textMuted)
                            Text("Log your weight to see your progress chart")
                                .font(.bodyMd)
                                .foregroundColor(.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(Color.surface.opacity(0.4))
        .refreshable { await vm.load() }
    }

    private var weightChart: some View {
        // Simple weight line chart using Canvas
        // In production replace with Swift Charts (iOS 16+)
        GeometryReader { geo in
            let weights = vm.weightHistory.map { $0.weightKg }
            guard let minW = weights.min(), let maxW = weights.max(), maxW > minW else {
                return AnyView(
                    Text("Not enough data yet")
                        .font(.bodySm)
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                )
            }
            let range = maxW - minW
            let points = weights.enumerated().map { i, w -> CGPoint in
                let x = geo.size.width * CGFloat(i) / CGFloat(weights.count - 1)
                let y = geo.size.height * CGFloat(1 - (w - minW) / range)
                return CGPoint(x: x, y: y)
            }
            return AnyView(
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    ctx.stroke(path, with: .color(.brandGreen), lineWidth: 2)
                    points.forEach { pt in
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x-3, y: pt.y-3, width: 6, height: 6)),
                                 with: .color(.brandGreen))
                    }
                }
            )
        }
        .frame(height: 120)
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
