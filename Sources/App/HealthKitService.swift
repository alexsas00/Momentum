import Foundation
import HealthKit

/// Read-only daily summaries for the auto metrics.
/// Results are merged into MomentumStore so widgets never query HealthKit directly.
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.stepCount),
        ]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Daily sums for the last `days` days, keyed "yyyy-MM-dd".
    /// kind must be one of the health kinds; unit conversion matches Metric.unit.
    func dailyTotals(kind: MetricKind, days: Int) async throws -> [String: Double] {
        guard isAvailable else { return [:] }

        let (type, unit): (HKQuantityType, HKUnit)
        switch kind {
        case .healthActiveEnergy: (type, unit) = (HKQuantityType(.activeEnergyBurned), .kilocalorie())
        case .healthDistance: (type, unit) = (HKQuantityType(.distanceWalkingRunning), .meterUnit(with: .kilo))
        case .healthSteps: (type, unit) = (HKQuantityType(.stepCount), .count())
        default: return [:]
        }

        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86_400)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: cal.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { cont.resume(throwing: error); return }
                var out: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let sum = stat.sumQuantity() {
                        let v = sum.doubleValue(for: unit)
                        out[Days.key(stat.startDate)] = (v * 10).rounded() / 10
                    }
                }
                cont.resume(returning: out)
            }
            self.store.execute(query)
        }
    }

    /// Refresh every health metric in the store (call on launch + pull-to-refresh).
    @MainActor
    func syncAll(into momentum: MomentumStore, days: Int = 365) async {
        for metric in momentum.metrics where metric.kind.isHealth && !metric.isArchived {
            if let daily = try? await dailyTotals(kind: metric.kind, days: days) {
                momentum.mergeHealth(metric.id, daily: daily)
            }
        }
    }
}
