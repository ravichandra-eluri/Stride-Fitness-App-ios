import Foundation
import HealthKit
import Observation

struct ActivitySummary {
    var steps: Int = 0
    var activeCalories: Int = 0
    var workouts: [WorkoutEntry] = []
}

struct WorkoutEntry: Identifiable {
    let id: UUID
    let name: String
    let durationMinutes: Int
    let calories: Int
    let date: Date
}

@Observable
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    var isAuthorized = false
    var activity = ActivitySummary()

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.workoutType(),
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            await loadToday()
        } catch {
            print("[HealthKit] auth error: \(error)")
        }
    }

    func loadToday() async {
        guard isAvailable else { return }
        async let steps   = fetchSteps()
        async let cals    = fetchActiveCalories()
        async let workouts = fetchRecentWorkouts()
        activity = ActivitySummary(
            steps: await steps,
            activeCalories: await cals,
            workouts: await workouts
        )
    }

    private func fetchSteps() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: Int(val))
            }
            store.execute(q)
        }
    }

    private func fetchActiveCalories() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                cont.resume(returning: Int(val))
            }
            store.execute(q)
        }
    }

    private func fetchRecentWorkouts() async -> [WorkoutEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 10, sortDescriptors: [sort]) { _, samples, _ in
                let entries = (samples as? [HKWorkout] ?? []).map { w in
                    WorkoutEntry(
                        id: w.uuid,
                        name: w.workoutActivityType.displayName,
                        durationMinutes: Int(w.duration / 60),
                        calories: Int(w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0),
                        date: w.startDate
                    )
                }
                cont.resume(returning: entries)
            }
            store.execute(q)
        }
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running:          return "Run"
        case .cycling:          return "Cycling"
        case .walking:          return "Walk"
        case .swimming:         return "Swim"
        case .yoga:             return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking:           return "Hike"
        case .dance:            return "Dance"
        case .elliptical:       return "Elliptical"
        case .rowing:           return "Rowing"
        case .pilates:          return "Pilates"
        default:                return "Workout"
        }
    }
}
