import SwiftUI
import Charts
import HealthKit
import AVFoundation

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

    var isLookingUp = false

    var isValid: Bool { !foodName.isEmpty && (calories ?? 0) > 0 }

    func applyNutrition(_ n: FoodNutrition) {
        foodName   = n.name
        calories   = n.calories
        proteinG   = n.proteinG
        carbsG     = n.carbsG
        fatG       = n.fatG
        servingSize = n.servingSize.isEmpty ? "1 serving" : n.servingSize
        logMethod  = "manual"
    }

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
    @State private var showCamera = false
    @FocusState private var focusedField: Field?

    var onLogged: (() -> Void)? = nil

    let mealTypes = ["breakfast", "lunch", "snack", "dinner"]

    enum Field: Hashable { case foodName, calories, serving, protein, carbs, fat }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {

                    // Log method selector
                    HStack(spacing: Spacing.sm) {
                        logMethodButton(icon: "barcode.viewfinder", label: "Scan",   method: "barcode")
                        logMethodButton(icon: "camera.fill",         label: "Photo",  method: "photo")
                        logMethodButton(icon: "list.bullet",         label: "Manual", method: "manual")
                    }

                    if vm.logMethod == "manual" {
                        manualForm
                    } else if vm.logMethod == "barcode" {
                        BarcodeScannerCard(vm: vm)
                    } else {
                        PhotoAnalysisCard(vm: vm, showCamera: $showCamera)
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { image in
                showCamera = false
                Task {
                    vm.isLookingUp = true
                    vm.error = nil
                    guard let jpeg = image.jpegData(compressionQuality: 0.7) else { return }
                    let b64 = jpeg.base64EncodedString()
                    do {
                        let nutrition = try await APIClient.shared.analyzePhoto(imageBase64: b64)
                        vm.applyNutrition(nutrition)
                    } catch {
                        vm.error = "Couldn't analyse photo. Fill in manually."
                        vm.logMethod = "manual"
                    }
                    vm.isLookingUp = false
                }
            } onCancel: {
                showCamera = false
                vm.logMethod = "manual"
            }
        }
    }

    private var manualForm: some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                formField("Food name") {
                    TextField("e.g. Chicken rice bowl", text: $vm.foodName)
                        .focused($focusedField, equals: .foodName)
                }
                formField("Meal type") {
                    Picker("", selection: $vm.mealType) {
                        ForEach(mealTypes, id: \.self) { Text($0.capitalized).tag($0) }
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
                            .keyboardType(.decimalPad).focused($focusedField, equals: .protein)
                    }
                    formField("Carbs (g)") {
                        TextField("0", value: $vm.carbsG, format: .number)
                            .keyboardType(.decimalPad).focused($focusedField, equals: .carbs)
                    }
                    formField("Fat (g)") {
                        TextField("0", value: $vm.fatG, format: .number)
                            .keyboardType(.decimalPad).focused($focusedField, equals: .fat)
                    }
                }
            }
        }
    }

    private func logMethodButton(icon: String, label: String, method: String) -> some View {
        let selected = vm.logMethod == method
        return Button { vm.logMethod = method } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon).font(.system(size: 20))
                    .foregroundColor(selected ? .brandGreen : .textMuted)
                Text(label).font(.labelSm)
                    .foregroundColor(selected ? .brandGreen : .textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(selected ? Color.brandGreenBg : Color.surface)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(selected ? Color.brandGreen : Color.border, lineWidth: selected ? 1.5 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
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

// ── Barcode scanner card ──────────────────────────────────────────────────────

struct BarcodeScannerCard: View {
    @Bindable var vm: LogFoodViewModel
    @State private var scannedCode: String?
    @State private var hasScanned = false

    var body: some View {
        WCard(padding: 0) {
            VStack(spacing: 0) {
                if vm.isLookingUp {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Looking up product…").font(.bodyMd).foregroundColor(.textMuted)
                    }
                    .frame(height: 240)
                } else {
                    BarcodeScannerView { code in
                        guard !hasScanned else { return }
                        hasScanned = true
                        Haptics.notify(.success)
                        Task {
                            vm.isLookingUp = true
                            vm.error = nil
                            do {
                                let nutrition = try await APIClient.shared.lookupBarcode(code)
                                vm.applyNutrition(nutrition)
                            } catch {
                                vm.error = "Product not found. Fill in manually."
                                vm.logMethod = "manual"
                            }
                            vm.isLookingUp = false
                        }
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                    HStack {
                        Image(systemName: "viewfinder")
                            .foregroundColor(.textMuted)
                        Text("Point camera at a barcode")
                            .font(.bodySm).foregroundColor(.textMuted)
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }
}

// ── Photo analysis card ───────────────────────────────────────────────────────

struct PhotoAnalysisCard: View {
    @Bindable var vm: LogFoodViewModel
    @Binding var showCamera: Bool

    var body: some View {
        WCard {
            VStack(spacing: Spacing.md) {
                if vm.isLookingUp {
                    ProgressView()
                    Text("AI is estimating calories…").font(.bodyMd).foregroundColor(.textMuted)
                } else {
                    Image(systemName: "camera.fill").font(.system(size: 48)).foregroundColor(.textMuted)
                    Text("Take a photo and AI will estimate the calories")
                        .font(.bodyMd).foregroundColor(.textMuted).multilineTextAlignment(.center)
                    WButton(title: "Open camera") { showCamera = true }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
        }
    }
}

// ── AVFoundation barcode scanner ──────────────────────────────────────────────

struct BarcodeScannerView: UIViewRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            let label = UILabel()
            label.text = "Camera access required"
            label.textColor = .white
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }

        let session = AVCaptureSession()
        context.coordinator.session = session
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .qr, .code128]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        context.coordinator.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onFound: (String) -> Void
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var fired = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !fired,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue else { return }
            fired = true
            session?.stopRunning()
            onFound(value)
        }
    }
}

// ── UIImagePickerController wrapper ──────────────────────────────────────────

struct CameraPickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
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
    @State private var hk = HealthKitManager.shared

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
        .task {
            await vm.load()
            if hk.isAvailable {
                await hk.requestAuthorization()
            }
        }
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

                // Apple Health activity
                if hk.isAvailable {
                    activitySection
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

    private var activitySection: some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Today's Activity", systemImage: "figure.run")
                        .font(.labelMd)
                    Spacer()
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Apple Health")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                    activityTile(value: "\(hk.activity.steps.formatted())",
                                 label: "Steps",
                                 icon: "figure.walk",
                                 color: .brandGreen)
                    activityTile(value: "\(hk.activity.activeCalories) kcal",
                                 label: "Active cal",
                                 icon: "flame.fill",
                                 color: .warning)
                }

                if !hk.activity.workouts.isEmpty {
                    Divider()
                    Text("Recent workouts")
                        .font(.labelSm)
                        .foregroundColor(.textMuted)
                    ForEach(hk.activity.workouts.prefix(3)) { w in
                        HStack {
                            Image(systemName: workoutIcon(w.name))
                                .frame(width: 28)
                                .foregroundColor(.brandGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).font(.labelSm)
                                Text(w.date, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(w.durationMinutes) min").font(.labelSm)
                                if w.calories > 0 {
                                    Text("\(w.calories) kcal")
                                        .font(.caption)
                                        .foregroundColor(.textMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func activityTile(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.labelMd)
                Text(label).font(.caption).foregroundColor(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func workoutIcon(_ name: String) -> String {
        switch name {
        case "Run":      return "figure.run"
        case "Walk":     return "figure.walk"
        case "Cycling":  return "figure.outdoor.cycle"
        case "Swim":     return "figure.pool.swim"
        case "Yoga":     return "figure.yoga"
        case "Strength": return "dumbbell.fill"
        case "HIIT":     return "bolt.fill"
        case "Hike":     return "mountain.2.fill"
        default:         return "figure.mixed.cardio"
        }
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
