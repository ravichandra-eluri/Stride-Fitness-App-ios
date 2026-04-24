import Foundation

// ── Auth ──────────────────────────────────────────────────────────────────────

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let isNewUser: Bool
}

// ── Profile ───────────────────────────────────────────────────────────────────

struct UserProfile: Codable {
    var name: String
    var age: Int
    var gender: String
    var heightCm: Int
    var currentWeightKg: Double
    var goalWeightKg: Double
    var timelineMonths: Int
    var activityLevel: String
    var dailyMinutes: Int
    var dietPrefs: [String]
    var primaryGoal: String
    var calorieTarget: Int
    var proteinTargetG: Int
    var carbsTargetG: Int
    var fatTargetG: Int
    var goalDate: String?
}

// ── Onboarding ────────────────────────────────────────────────────────────────

struct OnboardingPlanResponse: Decodable {
    let calorieTarget: Int
    let proteinTarget: Int
    let carbsTarget: Int
    let fatTarget: Int
    let weeklyLossKg: Double
    let goalDate: String
    let coachMessage: String
    let planSummary: String

    private enum CodingKeys: String, CodingKey {
        case calorieTarget
        case proteinTarget
        case carbsTarget
        case fatTarget
        case weeklyLossKg
        case goalDate
        case coachMessage
        case planSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calorieTarget = Int((try container.decodeIfPresent(Double.self, forKey: .calorieTarget)) ?? 0)
        proteinTarget = Int((try container.decodeIfPresent(Double.self, forKey: .proteinTarget)) ?? 0)
        carbsTarget   = Int((try container.decodeIfPresent(Double.self, forKey: .carbsTarget)) ?? 0)
        fatTarget     = Int((try container.decodeIfPresent(Double.self, forKey: .fatTarget)) ?? 0)
        weeklyLossKg = try container.decodeIfPresent(Double.self, forKey: .weeklyLossKg) ?? 0
        goalDate = try container.decodeIfPresent(String.self, forKey: .goalDate) ?? "Goal date coming soon"
        coachMessage = try container.decodeIfPresent(String.self, forKey: .coachMessage) ?? "Your plan is ready. Start with one consistent day and build from there."
        planSummary = try container.decodeIfPresent(String.self, forKey: .planSummary) ?? "Your calorie target and meal plan are ready. We’ll keep refining your guidance as you log progress."
    }
}

// ── Food lookup ───────────────────────────────────────────────────────────────

struct FoodNutrition: Decodable {
    let name: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let servingSize: String
}

// ── Meal plan ─────────────────────────────────────────────────────────────────

struct Meal: Codable, Identifiable {
    var id: String { name + mealType }
    let name: String
    let calories: Int
    // Backend sends these as floats (e.g. 14.5). Decoding as Int would fail
    // and kill the whole meal-plan response, so keep them as Double and
    // format for display at the view layer.
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    // Claude prompt doesn't yet ask for prep time, so treat as optional.
    let prepMinutes: Int?
    let mealType: String // breakfast | lunch | snack | dinner
    let description: String?
    let ingredients: [String]?
}

struct DayPlan: Codable, Identifiable {
    var id: String { day }
    let day: String
    let meals: [Meal]
    let totalCalories: Int
}

struct WeeklyMealPlan: Codable {
    let week: String
    let days: [DayPlan]
    let avgDailyCalories: Int
}

struct MealSwapResponse: Decodable {
    let alternatives: [Meal]
}

// ── Daily log ─────────────────────────────────────────────────────────────────

struct DailyLog: Decodable {
    let id: String
    let caloriesEaten: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let onPlan: Bool
    let streakDay: Int
}

struct FoodEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var mealType: String
    var foodName: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var servingSize: String
    var logMethod: String // barcode | photo | manual | plan
    var barcode: String?
}

struct LogFoodResponse: Decodable {
    let entryId: String
    let totalCalories: Int
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
}

struct TodayLogResponse: Decodable {
    var log: DailyLog?
    var entries: [FoodEntry]?
}

// ── Coach ─────────────────────────────────────────────────────────────────────

struct CoachMessage: Decodable, Identifiable {
    let id: String
    let message: String
    let tip: String
    let priorityMeal: String?
    let tone: String
}

// ── Progress ──────────────────────────────────────────────────────────────────

struct WeeklySummary: Decodable {
    let avgCalories: Int
    let avgProteinG: Double
    let daysOnPlan: Int
    let daysLogged: Int
    let bestStreak: Int
}

struct WeightEntry: Decodable, Identifiable {
    var id: String { loggedAt }
    let weightKg: Double
    let loggedAt: String

    var loggedAtDate: Date {
        if let date = DateFormatters.iso8601WithFractional.date(from: loggedAt) {
            return date
        }
        if let date = DateFormatters.iso8601.date(from: loggedAt) {
            return date
        }
        return .distantPast
    }
}

// ── Subscription ─────────────────────────────────────────────────────────────

struct SubscriptionStatus: Decodable {
    let status: String // active | expired | free_trial
}

private enum DateFormatters {
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
