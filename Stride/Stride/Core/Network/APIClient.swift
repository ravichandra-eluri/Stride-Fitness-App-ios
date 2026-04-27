import Foundation

// ── API Client ────────────────────────────────────────────────────────────────
// Single async/await HTTP client. Handles auth headers, token refresh,
// and JSON decoding in one place.

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL"
        case .unauthorized:        return "Please sign in again"
        case .serverError(_, let m): return friendlyServerMessage(m)
        case .decodingError:       return "We couldn't read the server response. Please try again."
        case .networkError(let e): return e.localizedDescription
        }
    }

    private func friendlyServerMessage(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "The server ran into an issue. Please try again." }
        // If the server sent JSON { "error": "..." }, extract the message.
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (obj["error"] ?? obj["message"]) as? String {
            return message
        }
        return trimmed
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Base URL — read from `STRIDE_API_BASE_URL` in the app's Info.plist so
    /// the same binary can be retargeted for staging / local dev without a
    /// code change. Falls back to the production Cloud Run URL.
    private let baseURL: String = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "STRIDE_API_BASE_URL") as? String,
           !configured.isEmpty {
            return configured
        }
        return "https://stride-backend-zyytfut7bq-uc.a.run.app"
    }()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 160
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private struct EmptyBody: Decodable {}

    // ── Core request method ───────────────────────────────────────────────

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let localDateFormatter = DateFormatter()
        localDateFormatter.dateFormat = "yyyy-MM-dd"
        req.setValue(localDateFormatter.string(from: Date()), forHTTPHeaderField: "X-Local-Date")

        if requiresAuth {
            let token = try await validAccessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            req.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode == 401 && requiresAuth {
            // Token expired mid-request — try refresh once
            try await refreshTokens()
            return try await request(method, path: path, body: body, requiresAuth: requiresAuth)
        }

        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw APIError.serverError(http.statusCode, msg)
        }

        // Allow callers to use `EmptyBody` for endpoints that return no payload.
        if T.self == EmptyBody.self {
            return EmptyBody() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // Convenience methods
    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path: path)
    }

    func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request("PATCH", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyBody = try await request("DELETE", path: path)
    }

    // ── Token management ──────────────────────────────────────────────────

    private func validAccessToken() async throws -> String {
        guard let token = Keychain.get("access_token") else {
            throw APIError.unauthorized
        }
        return token
    }

    private func refreshTokens() async throws {
        guard let refreshToken = Keychain.get("refresh_token") else {
            throw APIError.unauthorized
        }

        struct RefreshBody: Encodable { let refreshToken: String }
        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String
        }

        let res: RefreshResponse = try await request(
            "POST",
            path: "/api/auth/refresh",
            body: RefreshBody(refreshToken: refreshToken),
            requiresAuth: false
        )

        Keychain.set("access_token", value: res.accessToken)
        Keychain.set("refresh_token", value: res.refreshToken)
    }
}

// ── Typed API calls ───────────────────────────────────────────────────────────
// One function per backend endpoint. ViewModels call these directly.

extension APIClient {

    // Auth
    func signInWithApple(identityToken: String, email: String, fullName: String) async throws -> AuthResponse {
        struct Body: Encodable {
            let identityToken: String
            let email: String
            let fullName: String
        }
        return try await request("POST", path: "/api/auth/apple",
                                 body: Body(identityToken: identityToken, email: email, fullName: fullName),
                                 requiresAuth: false)
    }

    // Onboarding
    func completeOnboarding(profile: UserProfile) async throws -> OnboardingPlanResponse {
        try await post("/api/onboarding/complete", body: profile)
    }

    // Profile
    func getProfile() async throws -> UserProfile {
        try await get("/api/profile")
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await patch("/api/profile", body: profile)
    }

    // Meal plans
    func getMealPlan() async throws -> WeeklyMealPlan {
        try await get("/api/meals/plan")
    }

    func regenerateMealPlan() async throws -> WeeklyMealPlan {
        struct Empty: Encodable {}
        return try await post("/api/meals/regenerate", body: Empty())
    }

    func swapMeal(mealPlanID: String, day: String, meal: Meal, filter: String) async throws -> [Meal] {
        struct Body: Encodable {
            let mealPlanId: String
            let day: String
            let meal: Meal
            let filter: String
        }
        return try await post("/api/meals/swap",
                              body: Body(mealPlanId: mealPlanID, day: day, meal: meal, filter: filter))
    }

    // Food logging
    func logFood(_ entry: FoodEntry) async throws -> LogFoodResponse {
        try await post("/api/log/food", body: entry)
    }

    func getTodayLog() async throws -> TodayLogResponse {
        try await get("/api/log/today")
    }

    func deleteFoodEntry(id: String) async throws {
        try await delete("/api/log/food/\(id)")
    }

    func deleteAccount() async throws {
        try await delete("/api/account")
    }

    func logWeight(_ kg: Double, note: String = "") async throws {
        struct Body: Encodable { let weightKg: Double; let note: String }
        struct Empty: Decodable {}
        let _: Empty = try await post("/api/log/weight", body: Body(weightKg: kg, note: note))
    }

    // Progress
    func getWeeklySummary() async throws -> WeeklySummary {
        try await get("/api/progress/weekly")
    }

    func getWeightHistory() async throws -> [WeightEntry] {
        try await get("/api/progress/weights")
    }

    // Coach
    func getTodayCoachMessage() async throws -> CoachMessage {
        try await get("/api/coach/today")
    }

    // Food lookup
    func lookupBarcode(_ barcode: String) async throws -> FoodNutrition {
        try await get("/api/food/barcode/\(barcode)")
    }

    func analyzePhoto(imageBase64: String) async throws -> FoodNutrition {
        struct Body: Encodable { let imageBase64: String }
        return try await post("/api/food/analyze-photo", body: Body(imageBase64: imageBase64))
    }

    // Device token
    func registerDeviceToken(_ token: String, deviceName: String) async throws {
        struct Body: Encodable { let token: String; let deviceName: String }
        struct Empty: Decodable {}
        let _: Empty = try await post("/api/device/register",
                                      body: Body(token: token, deviceName: deviceName))
    }
}
