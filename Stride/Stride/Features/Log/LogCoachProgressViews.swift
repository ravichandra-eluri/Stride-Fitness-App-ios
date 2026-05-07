import SwiftUI
import Charts
import HealthKit
import AVFoundation

// ── Log Food View ─────────────────────────────────────────────────────────────

struct FoodSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

// Open Food Facts response shapes (internal to food search)
private struct OFFResponse: Decodable {
    let products: [OFFProduct]
}
private struct OFFProduct: Decodable {
    let productName: String?
    let nutriments: OFFNutriments?
    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case nutriments
    }
}
private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    enum CodingKeys: String, CodingKey {
        case energyKcal100g    = "energy-kcal_100g"
        case proteins100g      = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g           = "fat_100g"
    }
}

@Observable
@MainActor
class LogFoodViewModel {
    var foodName: String = ""
    // Per-serving base values. Optional so a fresh field renders empty
    // (placeholder) instead of "0". Renamed from calories/proteinG/... to
    // make it explicit these are *per serving*, not what gets logged.
    var baseCalories: Int? = nil
    var baseProteinG: Double? = nil
    var baseCarbsG: Double? = nil
    var baseFatG: Double? = nil
    // Multiplier the user adjusts for "I ate 2 servings". Defaults to 1 so
    // typed-only entries (no quantity tweak) behave the same as before.
    var servings: Double = 1.0
    var mealType: String = "lunch"
    var servingSize: String = "1 serving"
    var logMethod: String = "photo"
    var isLogging = false
    var successMessage: String?
    var error: String?
    var isLookingUp = false

    var suggestions: [FoodSuggestion] = []
    var showSuggestions = false
    var isSearching = false
    var noResults = false  // True when search completed but returned nothing — drives empty-state UI.
    var isEstimatingByAI = false  // True while POST /food/analyze-name is in flight.
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchSeq: UInt64 = 0  // Monotonic ID to discard stale responses.
    @ObservationIgnored private var lastQueriedNorm = ""

    // Live totals = base × servings. These are what gets logged.
    var totalCalories: Int { Int((Double(baseCalories ?? 0) * servings).rounded()) }
    var totalProteinG: Double { (baseProteinG ?? 0) * servings }
    var totalCarbsG:   Double { (baseCarbsG   ?? 0) * servings }
    var totalFatG:     Double { (baseFatG     ?? 0) * servings }

    var isValid: Bool { !foodName.isEmpty && totalCalories > 0 && servings > 0 }

    func incrementServings() {
        servings = min(round((servings + 0.5) * 10) / 10, 99)
        Haptics.selection()
    }

    func decrementServings() {
        servings = max(round((servings - 0.5) * 10) / 10, 0.5)
        Haptics.selection()
    }

    func applyNutrition(_ n: FoodNutrition) {
        // Suppress the foodName onChange from re-triggering OFF search after
        // we programmatically rewrite the name (Claude can return a canonical
        // name like "Chicken Biryani" different from the user's input).
        lastAppliedName = n.name
        searchTask?.cancel()
        foodName     = n.name
        baseCalories = n.calories
        baseProteinG = n.proteinG
        baseCarbsG   = n.carbsG
        baseFatG     = n.fatG
        servingSize  = n.servingSize.isEmpty ? "1 serving" : n.servingSize
        servings     = 1.0
        logMethod    = "manual"
        suggestions = []
        showSuggestions = false
        noResults = false
        isSearching = false
    }

    // Tracks the name last set by applySuggestion so onChange doesn't re-trigger a search.
    @ObservationIgnored private var lastAppliedName = ""

    func applySuggestion(_ s: FoodSuggestion) {
        searchTask?.cancel()
        lastAppliedName = s.name
        foodName     = s.name
        baseCalories = s.calories
        baseProteinG = s.proteinG
        baseCarbsG   = s.carbsG
        baseFatG     = s.fatG
        servingSize  = "100g"
        servings     = 1.0
        logMethod    = "manual"
        suggestions  = []
        showSuggestions = false
        isSearching  = false
    }

    func searchFood(_ query: String) {
        // Ignore the onChange that fires when applySuggestion programmatically sets foodName.
        if query == lastAppliedName {
            lastAppliedName = ""
            return
        }
        searchTask?.cancel()
        let norm = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard norm.count >= 2 else {
            suggestions = []
            showSuggestions = false
            isSearching = false
            noResults = false
            lastQueriedNorm = ""
            return
        }
        // Skip the network if the user retyped the same query (e.g. cursor moves).
        if norm == lastQueriedNorm && (!suggestions.isEmpty || noResults) {
            showSuggestions = true
            return
        }

        searchSeq &+= 1
        let mySeq = searchSeq
        isSearching = true
        showSuggestions = true
        noResults = false

        searchTask = Task { [weak self] in
            // 250ms debounce — short enough to feel snappy, long enough to skip
            // mid-typing characters.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            // Open Food Facts v2 search — much faster and more reliable than the
            // legacy cgi/search.pl endpoint. User-Agent is REQUIRED by OFF policy
            // to avoid IP-level rate limiting on anonymous traffic.
            // No sort_by — OFF defaults to relevance scoring against the query.
            // Adding "popularity_key" sorts by overall scan count (returns the
            // most-popular OFF products regardless of relevance to the query).
            var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/search")!
            comps.queryItems = [
                URLQueryItem(name: "search_terms", value: query),
                URLQueryItem(name: "fields",       value: "product_name,nutriments"),
                URLQueryItem(name: "page_size",    value: "20"),
            ]
            guard let url = comps.url else {
                await MainActor.run { self?.finishSearch(mySeq, results: [], norm: norm) }
                return
            }

            var req = URLRequest(url: url, timeoutInterval: 6)
            req.setValue("Stride/1.0 (iOS; chandra.sk59@gmail.com)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard !Task.isCancelled else { return }
                let response = try JSONDecoder().decode(OFFResponse.self, from: data)
                // OFF's relevance ranking is loose — it returns lots of
                // tangentially-matching results. Keep only products whose
                // name actually contains at least one query token, so
                // "chicken biryani" doesn't surface "Fromage Blanc Nature".
                let queryTokens = norm
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map { $0.lowercased() }
                    .filter { $0.count >= 3 }
                let results: [FoodSuggestion] = response.products.compactMap { p in
                    guard let name = p.productName, !name.isEmpty,
                          let n = p.nutriments,
                          let kcal = n.energyKcal100g, kcal > 0
                    else { return nil }
                    let lowerName = name.lowercased()
                    if !queryTokens.isEmpty,
                       !queryTokens.contains(where: { lowerName.contains($0) }) {
                        return nil
                    }
                    return FoodSuggestion(
                        name: name,
                        calories: Int(kcal),
                        proteinG: n.proteins100g ?? 0,
                        carbsG: n.carbohydrates100g ?? 0,
                        fatG: n.fat100g ?? 0
                    )
                }
                await MainActor.run { self?.finishSearch(mySeq, results: results, norm: norm) }
            } catch {
                await MainActor.run { self?.finishSearch(mySeq, results: [], norm: norm) }
            }
        }
    }

    /// Ask Claude to estimate per-serving nutrition for the typed food name.
    /// Used when OFF has no match (cooked / ethnic dishes) or as a fallback the
    /// user can opt into instead of typing values manually.
    func estimateByAI() async {
        let q = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isEstimatingByAI = true
        error = nil
        do {
            let n = try await APIClient.shared.analyzeName(q)
            applyNutrition(n)
            suggestions = []
            showSuggestions = false
            noResults = false
            Haptics.notify(.success)
        } catch {
            self.error = "Couldn't estimate. Fill in manually."
            Haptics.notify(.error)
        }
        isEstimatingByAI = false
    }

    /// Apply search results only if no newer search has been kicked off. Without
    /// this guard, a slow earlier response could clobber a faster newer one.
    private func finishSearch(_ seq: UInt64, results: [FoodSuggestion], norm: String) {
        guard seq == searchSeq else { return }
        suggestions = results
        showSuggestions = true
        noResults = results.isEmpty
        isSearching = false
        lastQueriedNorm = norm
    }

    func logFood() async -> Bool {
        guard isValid else { return false }
        isLogging = true
        error = nil
        // Persist totals (base × servings), not the per-serving base, so the
        // daily log reflects what the user actually ate.
        let loggedServingSize = servings == 1.0
            ? servingSize
            : "\(formatServings(servings)) × \(servingSize)"
        let entry = FoodEntry(
            mealType: mealType, foodName: foodName,
            calories: totalCalories,
            proteinG: totalProteinG,
            carbsG:   totalCarbsG,
            fatG:     totalFatG,
            servingSize: loggedServingSize, logMethod: logMethod
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
        baseCalories = nil; baseProteinG = nil; baseCarbsG = nil; baseFatG = nil
        servings = 1.0
        servingSize = "1 serving"
        suggestions = []
        showSuggestions = false
    }
}

// "1.5", "2", "0.5" — keeps it short for the logged servingSize string.
private func formatServings(_ s: Double) -> String {
    s.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(s))
        : String(format: "%.1f", s)
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
                        foodNameCard
                        if vm.showSuggestions && !vm.suggestions.isEmpty {
                            suggestionsCard
                            // Offer the AI estimate as an additional option even
                            // when OFF returned matches — many of those are
                            // niche branded products that may not be what the
                            // user actually ate.
                            aiEstimateCard(isPrimary: false)
                        } else if vm.showSuggestions && vm.noResults && !vm.isSearching {
                            // No OFF matches — promote the AI estimate as the
                            // primary path forward.
                            aiEstimateCard(isPrimary: true)
                        }
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

    // ── Food name card ──────────────────────────────────────────────────────
    private var foodNameCard: some View {
        WCard {
            formField("Food name") {
                HStack {
                    TextField("e.g. Chicken biryani", text: $vm.foodName)
                        .focused($focusedField, equals: .foodName)
                        .onChange(of: vm.foodName) { _, new in vm.searchFood(new) }
                    if vm.isSearching {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
        }
    }

    // ── AI estimate card ────────────────────────────────────────────────────
    // Single tap → calls Claude → fills the form. Two visual modes:
    //   isPrimary=true:  Big card, shown when OFF returned no matches.
    //                    Mentions explicitly there were no matches.
    //   isPrimary=false: Compact strip below OFF suggestions as an alternative.
    private func aiEstimateCard(isPrimary: Bool) -> some View {
        let trimmedName = vm.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            Task { await vm.estimateByAI() }
            focusedField = nil
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.brandGreen, .brandPurple],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: isPrimary ? 44 : 36, height: isPrimary ? 44 : 36)
                    if vm.isEstimatingByAI {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: isPrimary ? 18 : 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if isPrimary {
                        Text("No matches found")
                            .font(.labelSm)
                            .foregroundColor(.textMuted)
                        Text("Estimate \"\(trimmedName)\" with AI")
                            .font(.titleSm)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Or estimate with AI")
                            .font(.labelMd)
                            .foregroundColor(.primary)
                        Text("Better for home-cooked or ethnic dishes")
                            .font(.bodySm)
                            .foregroundColor(.textMuted)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: vm.isEstimatingByAI ? "ellipsis" : "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.brandGreen)
            }
            .padding(Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color.brandGreenBg.opacity(0.9), Color.brandPurpleBg.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.brandGreen.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(vm.isEstimatingByAI || trimmedName.isEmpty)
        .opacity(vm.isEstimatingByAI ? 0.85 : 1)
    }

    // ── Suggestions card ────────────────────────────────────────────────────
    // Sits *below* the food-name field (not within), styled as a clear,
    // tappable list. Each row pre-fills the form's per-serving base values.
    private var suggestionsCard: some View {
        WCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.brandGreen)
                    Text("Suggestions")
                        .font(.labelSm)
                        .foregroundColor(.brandGreen)
                    Spacer()
                    Text("\(vm.suggestions.count)")
                        .font(.labelSm)
                        .foregroundColor(.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                Divider()

                ForEach(Array(vm.suggestions.enumerated()), id: \.element.id) { i, s in
                    Button {
                        vm.applySuggestion(s)
                        focusedField = nil
                    } label: {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name)
                                    .font(.labelMd)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("P \(Int(s.proteinG))g · C \(Int(s.carbsG))g · F \(Int(s.fatG))g · per 100g")
                                    .font(.bodySm)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer(minLength: Spacing.sm)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(s.calories)")
                                    .font(.labelMd)
                                    .foregroundColor(.brandGreen)
                                Text("cal")
                                    .font(.caption2)
                                    .foregroundColor(.textMuted)
                            }
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.brandGreen)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < vm.suggestions.count - 1 {
                        Divider().padding(.leading, Spacing.md)
                    }
                }
            }
        }
    }

    // ── Manual form (everything except food name) ───────────────────────────
    private var manualForm: some View {
        WCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                formField("Meal type") {
                    Picker("", selection: $vm.mealType) {
                        ForEach(mealTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // Servings is the primary user control — most-touched, so it
                // sits up top right after meal type. Per-serving base values
                // (mostly auto-filled by suggestions / AI / photo) live below
                // for verification or manual edits.
                servingsStepper
                portionField

                Divider().opacity(0.4)

                HStack {
                    Text("Per serving")
                        .font(.labelSm)
                        .foregroundColor(.textMuted)
                    Spacer()
                }

                formField("Calories") {
                    TextField("e.g. 450", value: $vm.baseCalories, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .calories)
                }
                HStack(spacing: Spacing.md) {
                    formField("Protein (g)") {
                        TextField("0", value: $vm.baseProteinG, format: .number)
                            .keyboardType(.decimalPad).focused($focusedField, equals: .protein)
                    }
                    formField("Carbs (g)") {
                        TextField("0", value: $vm.baseCarbsG, format: .number)
                            .keyboardType(.decimalPad).focused($focusedField, equals: .carbs)
                    }
                    formField("Fat (g)") {
                        TextField("0", value: $vm.baseFatG, format: .number)
                            .keyboardType(.decimalPad).focused($focusedField, equals: .fat)
                    }
                }

                Divider().opacity(0.4)

                totalBanner
            }
        }
    }

    // ── Portion descriptor — paired with servings stepper ───────────────────
    // What "1 serving" actually is (e.g. "100g", "1 cup", "1 medium"). Used
    // for the audit trail in the logged entry; doesn't affect math.
    private var portionField: some View {
        HStack(spacing: Spacing.sm) {
            Text("of")
                .font(.bodySm)
                .foregroundColor(.textMuted)
            TextField("1 serving", text: $vm.servingSize)
                .focused($focusedField, equals: .serving)
                .font(.bodyMd)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("portion")
                .font(.bodySm)
                .foregroundColor(.textMuted)
            Spacer()
        }
    }

    // ── Servings stepper ─────────────────────────────────────────────────────
    // [-] [1.0] [+] — bumps in 0.5 steps (matches "I had half / one and a
    // half" intuition). Tap-and-hold not supported intentionally; keeps
    // accidental over-shoots low.
    private var servingsStepper: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("How many servings?")
                    .font(.labelMd)
                Text("Updates the total below")
                    .font(.bodySm)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            HStack(spacing: 0) {
                Button {
                    vm.decrementServings()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .foregroundColor(vm.servings <= 0.5 ? .textMuted : .brandGreen)
                }
                .disabled(vm.servings <= 0.5)
                .buttonStyle(.plain)

                Text(formatServings(vm.servings))
                    .font(.numericMd)
                    .foregroundColor(.primary)
                    .frame(minWidth: 48)
                    .contentTransition(.numericText())

                Button {
                    vm.incrementServings()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .foregroundColor(.brandGreen)
                }
                .buttonStyle(.plain)
            }
            .background(Color.brandGreenBg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.brandGreen.opacity(0.25), lineWidth: 1))
        }
    }

    // ── Total banner — large, brandGreen, updates live ───────────────────────
    private var totalBanner: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total")
                    .font(.labelSm)
                    .foregroundColor(.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(vm.totalCalories)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.brandGreen)
                        .contentTransition(.numericText())
                    Text("cal")
                        .font(.bodySm)
                        .foregroundColor(.textMuted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("P \(macroFormat(vm.totalProteinG))g")
                    .font(.labelSm)
                    .foregroundColor(.brandPurple)
                    .contentTransition(.numericText())
                HStack(spacing: Spacing.sm) {
                    Text("C \(macroFormat(vm.totalCarbsG))g")
                        .font(.labelSm)
                        .foregroundColor(.brandGreen)
                        .contentTransition(.numericText())
                    Text("F \(macroFormat(vm.totalFatG))g")
                        .font(.labelSm)
                        .foregroundColor(.warning)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.brandGreenBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .animation(.easeOut(duration: 0.2), value: vm.servings)
    }

    private func macroFormat(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
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
                    coachSkeleton
                } else if let msg = message {
                    coachContent(msg)
                } else {
                    emptyCoachView
                }
            }
            .tabBackground(.tintCoach)
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

    private var coachSkeleton: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                WSkeletonCard(lines: 4)
                WSkeletonCard(lines: 3)
                WSkeletonCard(lines: 1)
            }
            .padding(Spacing.md)
        }
    }

    private var emptyCoachView: some View {
        WEmptyState(
            icon: "bubble.left.fill",
            title: "No coach message yet",
            subtitle: "Your daily coaching message will appear here each morning.",
            ctaTitle: "Refresh",
            ctaAction: { Task { await load() } },
            tintColors: [.brandPurple, .brandGreen]
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
            if let latest = weightHistory.last {
                newWeight = latest.weightKg
            } else if let profile = try? await APIClient.shared.getProfile() {
                newWeight = profile.currentWeightKg
            }
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
                    progressSkeleton
                } else {
                    progressContent
                }
            }
            .tabBackground(.tintProgress)
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

    private var progressSkeleton: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        WCard { WSkeleton(height: 48, cornerRadius: 8) }
                    }
                }
                WSkeletonCard(lines: 4)
                WSkeletonCard(lines: 5)
            }
            .padding(Spacing.md)
        }
    }

    private var progressContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Weekly stats grid
                if let s = vm.summary {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                        WStatCard(value: "\(s.daysLogged)", label: "Days logged")
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
                                Text(w.date, style: .date)
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
