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
        case .serverError(let c, let m): return "Server error \(c): \(m)"
        case .decodingError(let e):return "Decode error: \(e)"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://your-cloudrun-url.run.app" // set after deploy
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

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

        if http.statusCode == 401 {
            // Token expired mid-request — try refresh once
            try await refreshTokens()
            return try await request(method, path: path, body: body, requiresAuth: requiresAuth)
        }

        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw APIError.serverError(http.statusCode, msg)
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

    func swapMeal(mealPlanID: String, day: String, meal: Meal, filter: String) async throws -> MealSwapResponse {
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

    // Device token
    func registerDeviceToken(_ token: String, deviceName: String) async throws {
        struct Body: Encodable { let token: String; let deviceName: String }
        struct Empty: Decodable {}
        let _: Empty = try await post("/api/device/register",
                                      body: Body(token: token, deviceName: deviceName))
    }
}
