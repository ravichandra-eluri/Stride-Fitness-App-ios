import Foundation
import HealthKit
import Observation

struct ActivitySummary {
    var steps: Int = 0
    var activeCalories: Int = 0
    var walkingDistanceM: Double = 0
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
        await loadDate(Date())
    }

    func loadDate(_ date: Date) async {
        guard isAvailable else { return }
        async let steps    = fetchSteps(for: date)
        async let cals     = fetchActiveCalories(for: date)
        async let workouts = fetchWorkouts(for: date)
        let s = await steps
        let w = await workouts
        var c = await cals
        // Fall back to summing workout calories when no activeEnergyBurned samples exist.
        // This happens when a 3rd-party app records a workout without writing discrete
        // activeEnergyBurned samples (e.g. iPhone walk sessions via Fitness app).
        if c == 0 { c = w.reduce(0) { $0 + $1.calories } }
        activity = ActivitySummary(steps: s, activeCalories: c, workouts: w)
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end: Date = cal.isDateInToday(date)
            ? Date()
            : (cal.date(byAdding: .day, value: 1, to: start) ?? start)
        return (start, end)
    }

    // Uses hourly-interval collection query with per-source sums, then takes the
    // MAX source per bucket. Summing across sources causes double-counting when
    // both iPhone and Apple Watch record steps for the same period.
    private func fetchSteps(for date: Date) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let (start, end) = dayBounds(for: date)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(hour: 1)
        let anchor = Calendar.current.startOfDay(for: date)

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: pred,
                options: [.cumulativeSum, .separateBySource],
                anchorDate: anchor,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, results, _ in
                guard let results else { cont.resume(returning: 0); return }
                var total: Double = 0
                results.enumerateStatistics(from: start, to: end) { stats, _ in
                    // Per hourly bucket, pick the source with the highest count.
                    // Paired devices like iPhone + Watch both write overlapping samples;
                    // taking MAX instead of sum avoids inflating the total.
                    let bucketMax = stats.sources?.compactMap { src in
                        stats.sumQuantity(for: src)?.doubleValue(for: .count())
                    }.max() ?? 0
                    total += bucketMax
                }
                cont.resume(returning: Int(total))
            }
            store.execute(q)
        }
    }

    private func fetchActiveCalories(for date: Date) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let (start, end) = dayBounds(for: date)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(hour: 1)
        let anchor = Calendar.current.startOfDay(for: date)

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: pred,
                options: [.cumulativeSum, .separateBySource],
                anchorDate: anchor,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, results, _ in
                guard let results else { cont.resume(returning: 0); return }
                var total: Double = 0
                results.enumerateStatistics(from: start, to: end) { stats, _ in
                    let bucketMax = stats.sources?.compactMap { src in
                        stats.sumQuantity(for: src)?.doubleValue(for: .kilocalorie())
                    }.max() ?? 0
                    total += bucketMax
                }
                cont.resume(returning: Int(total))
            }
            store.execute(q)
        }
    }

    private func fetchWorkouts(for date: Date) async -> [WorkoutEntry] {
        let (start, end) = dayBounds(for: date)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
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
