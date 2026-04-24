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
    @State private var mealReminderOn   = false
    @State private var mealReminderTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    @State private var eveningCheckInOn   = false
    @State private var eveningCheckInTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()

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
                    Toggle(isOn: $mealReminderOn) {
                        Label("Morning meal reminder", systemImage: "sunrise.fill")
                    }
                    .tint(.brandGreen)
                    .disabled(authStatus != .authorized)

                    if mealReminderOn {
                        DatePicker("Remind me at", selection: $mealReminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: mealReminderTime) { _, _ in scheduleMealReminder() }
                    }
                } header: {
                    Text("Daily reminders")
                } footer: {
                    Text("Get a nudge to log your breakfast and start the day on track.")
                }

                Section {
                    Toggle(isOn: $eveningCheckInOn) {
                        Label("Evening check-in", systemImage: "moon.stars.fill")
                    }
                    .tint(.brandGreen)
                    .disabled(authStatus != .authorized)

                    if eveningCheckInOn {
                        DatePicker("Remind me at", selection: $eveningCheckInTime, displayedComponents: .hourAndMinute)
                            .onChange(of: eveningCheckInTime) { _, _ in scheduleEveningCheckIn() }
                    }
                } footer: {
                    Text("A reminder to log your dinner and review today's progress.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: mealReminderOn) { _, on in
                if on { scheduleMealReminder() } else { center.removePendingNotificationRequests(withIdentifiers: ["meal_reminder"]) }
            }
            .onChange(of: eveningCheckInOn) { _, on in
                if on { scheduleEveningCheckIn() } else { center.removePendingNotificationRequests(withIdentifiers: ["evening_checkin"]) }
            }
            .task { await loadStatus() }
        }
    }

    private func loadStatus() async {
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus

        // Restore saved toggles
        mealReminderOn    = UserDefaults.standard.bool(forKey: "notif_meal_on")
        eveningCheckInOn  = UserDefaults.standard.bool(forKey: "notif_evening_on")
        if let t = UserDefaults.standard.object(forKey: "notif_meal_time") as? Date    { mealReminderTime = t }
        if let t = UserDefaults.standard.object(forKey: "notif_evening_time") as? Date { eveningCheckInTime = t }
    }

    private func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authStatus = granted ? .authorized : .denied
        } catch {
            print("[notif] requestAuthorization: \(error)")
        }
    }

    private func scheduleMealReminder() {
        guard authStatus == .authorized else { return }
        UserDefaults.standard.set(true, forKey: "notif_meal_on")
        UserDefaults.standard.set(mealReminderTime, forKey: "notif_meal_time")

        let content = UNMutableNotificationContent()
        content.title = "Time to log breakfast 🌅"
        content.body  = "Start your day strong — log your first meal in Stride."
        content.sound = .default

        var comps = Calendar.current.dateComponents([.hour, .minute], from: mealReminderTime)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "meal_reminder", content: content, trigger: trigger))
    }

    private func scheduleEveningCheckIn() {
        guard authStatus == .authorized else { return }
        UserDefaults.standard.set(true, forKey: "notif_evening_on")
        UserDefaults.standard.set(eveningCheckInTime, forKey: "notif_evening_time")

        let content = UNMutableNotificationContent()
        content.title = "Evening check-in 🌙"
        content.body  = "How did today go? Log your dinner and see today's progress in Stride."
        content.sound = .default

        var comps = Calendar.current.dateComponents([.hour, .minute], from: eveningCheckInTime)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "evening_checkin", content: content, trigger: trigger))
    }
}
