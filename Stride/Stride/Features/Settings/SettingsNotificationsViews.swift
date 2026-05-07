import SwiftUI
import UserNotifications

// ── Edit Profile (Settings) ───────────────────────────────────────────────────

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saved = false

    // Editable fields
    @State private var currentWeight = ""
    @State private var goalWeight    = ""
    @State private var dailyMinutes  = ""
    @State private var activityLevel = "moderately_active"
    @State private var dietPrefs: Set<String> = []

    private let activityLevels = [
        ("sedentary",          "Sedentary",           "Little or no exercise"),
        ("lightly_active",     "Lightly Active",      "1-3 days/week"),
        ("moderately_active",  "Moderately Active",   "3-5 days/week"),
        ("very_active",        "Very Active",         "6-7 days/week"),
        ("extra_active",       "Extra Active",        "Twice daily / hard labour"),
    ]

    private let allDietPrefs = [
        "vegetarian", "vegan", "gluten-free", "dairy-free",
        "keto", "paleo", "halal", "kosher", "low-carb", "high-protein"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Current stats") {
                    HStack {
                        Text("Current weight (kg)")
                        Spacer()
                        TextField("e.g. 75.0", text: $currentWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("Goal weight (kg)")
                        Spacer()
                        TextField("e.g. 68.0", text: $goalWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("Daily workout (min)")
                        Spacer()
                        TextField("e.g. 30", text: $dailyMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }

                Section("Activity level") {
                    ForEach(activityLevels, id: \.0) { key, title, subtitle in
                        Button {
                            activityLevel = key
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).foregroundColor(.primary)
                                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if activityLevel == key {
                                    Image(systemName: "checkmark").foregroundColor(.brandGreen)
                                }
                            }
                        }
                    }
                }

                Section("Diet preferences") {
                    FlowLayout(items: allDietPrefs) { pref in
                        Button {
                            if dietPrefs.contains(pref) { dietPrefs.remove(pref) }
                            else { dietPrefs.insert(pref) }
                        } label: {
                            Text(pref.capitalized)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(dietPrefs.contains(pref) ? Color.brandGreen : Color.secondary.opacity(0.15))
                                .foregroundColor(dietPrefs.contains(pref) ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                if let err = saveError {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.brandGreen)
                        } else {
                            Text("Save").bold()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task { await loadProfile() }
        }
        .overlay {
            if saved {
                VStack {
                    Spacer()
                    Label("Saved!", systemImage: "checkmark.circle.fill")
                        .padding()
                        .background(Color.brandGreen)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(), value: saved)
    }

    private func loadProfile() async {
        profile = try? await APIClient.shared.getProfile()
        guard let p = profile else { return }
        currentWeight = String(format: "%.1f", p.currentWeightKg)
        goalWeight    = String(format: "%.1f", p.goalWeightKg)
        dailyMinutes  = "\(p.dailyMinutes)"
        activityLevel = p.activityLevel
        dietPrefs     = Set(p.dietPrefs)
    }

    private func save() async {
        guard var p = profile else { return }
        if let v = Double(currentWeight) { p.currentWeightKg = v }
        if let v = Double(goalWeight)    { p.goalWeightKg = v }
        if let v = Int(dailyMinutes)     { p.dailyMinutes = v }
        p.activityLevel = activityLevel
        p.dietPrefs     = Array(dietPrefs)

        isSaving = true
        saveError = nil
        do {
            profile = try await APIClient.shared.updateProfile(p)
            Haptics.notify(.success)
            saved = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            saved = false
            dismiss()
        } catch {
            saveError = error.localizedDescription
            Haptics.notify(.error)
        }
        isSaving = false
    }
}

// Simple flow/wrapping layout for diet preference chips
struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geo in
            generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        let spacing: CGFloat = 8

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if abs(x - d.width) > geo.size.width {
                            x = 0; y -= d.height + spacing
                        }
                        let result = x
                        if item == items.last { x = 0 } else { x -= d.width + spacing }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = y
                        if item == items.last { y = 0 }
                        return result
                    }
            }
        }
        .background(heightReader($totalHeight))
    }

    private func heightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: HeightKey.self, value: geo.size.height)
        }
        .onPreferenceChange(HeightKey.self) { binding.wrappedValue = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// ── Notifications Settings ────────────────────────────────────────────────────

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    // Per-reminder toggle + time state, keyed by definition id.
    @State private var enabled: [String: Bool] = [:]
    @State private var times:   [String: Date] = [:]

    private let center = UNUserNotificationCenter.current()

    var body: some View {
        NavigationStack {
            Form {
                // Permission banner
                if authStatus == .denied {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notifications are blocked", systemImage: "bell.slash.fill")
                                .foregroundColor(.orange)
                            Text("Enable them in Settings → Stride to receive reminders.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                } else if authStatus == .notDetermined {
                    Section {
                        Button {
                            Task { await requestPermission() }
                        } label: {
                            Label("Enable notifications", systemImage: "bell.badge")
                                .foregroundColor(.brandGreen)
                        }
                    }
                }

                Section {
                    ForEach(MealReminders.all) { def in
                        reminderSection(def)
                    }
                } header: {
                    Text("Daily meal reminders")
                } footer: {
                    Text("Local time. Stride sends a single quiet nudge per meal.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadStatus() }
        }
    }

    @ViewBuilder
    private func reminderSection(_ def: MealReminders.Definition) -> some View {
        let isOn = Binding<Bool>(
            get: { enabled[def.id] ?? false },
            set: { newValue in
                enabled[def.id] = newValue
                if newValue {
                    MealReminders.schedule(def, at: times[def.id] ?? MealReminders.savedTime(def))
                } else {
                    MealReminders.cancel(def)
                }
            }
        )
        let time = Binding<Date>(
            get: { times[def.id] ?? MealReminders.savedTime(def) },
            set: { newValue in
                times[def.id] = newValue
                if enabled[def.id] == true {
                    MealReminders.schedule(def, at: newValue)
                }
            }
        )

        Toggle(isOn: isOn) {
            Label(def.title, systemImage: def.icon)
        }
        .tint(.brandGreen)
        .disabled(authStatus != .authorized)

        if isOn.wrappedValue {
            DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
        }
    }

    private func loadStatus() async {
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus
        for def in MealReminders.all {
            enabled[def.id] = MealReminders.isEnabled(def)
            times[def.id]   = MealReminders.savedTime(def)
        }
    }

    private func requestPermission() async {
        authStatus = await MealReminders.requestAndEnableAll()
        // Pick up any reminders that got auto-enabled by the helper.
        for def in MealReminders.all {
            enabled[def.id] = MealReminders.isEnabled(def)
            times[def.id]   = MealReminders.savedTime(def)
        }
    }
}
