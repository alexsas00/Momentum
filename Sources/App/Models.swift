import Foundation
import SwiftUI
import WidgetKit

// MARK: - App Group

enum AppGroup {
    /// Preferred id — must match the App Groups entitlement on BOTH targets.
    /// When the app is re-signed for sideloading (Sideloadly / SideStore / free
    /// personal team), the group is often renamed (e.g. "group.TEAMID.momentum.shared").
    /// `id` resolves the *actual* group at runtime so app and widget keep sharing data.
    static let preferredID = "group.momentum.shared"

    static let id: String = {
        // 1. The entitlement we shipped with still works → use it.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: preferredID) != nil {
            return preferredID
        }
        // 2. Re-signed build → read the real group from the embedded provisioning profile.
        if let fromProfile = groupIDFromEmbeddedProfile(),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: fromProfile) != nil {
            return fromProfile
        }
        return preferredID
    }()

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    /// Extracts `com.apple.security.application-groups` from embedded.mobileprovision
    /// (present in both the app bundle and the widget .appex bundle after signing).
    private static func groupIDFromEmbeddedProfile() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>") else { return nil }
        let xml = String(raw[start.lowerBound..<end.upperBound])
        guard let plist = try? PropertyListSerialization.propertyList(
                from: Data(xml.utf8), format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return nil }
        // Prefer a group that looks like ours; otherwise take the first.
        return groups.first { $0.hasSuffix("momentum.shared") } ?? groups.first
    }
}

// MARK: - Metric model

enum MetricKind: String, Codable, CaseIterable, Identifiable {
    case healthActiveEnergy   // kcal, auto
    case healthDistance       // km, auto
    case healthSteps          // steps, auto
    case manualBinary         // "day without sugar" — 0/1
    case manualQuantity       // "glasses of water" — count

    var id: String { rawValue }
    var isHealth: Bool {
        switch self {
        case .healthActiveEnergy, .healthDistance, .healthSteps: return true
        default: return false
        }
    }
    var label: String {
        switch self {
        case .healthActiveEnergy: return "Health · Active energy"
        case .healthDistance: return "Health · Run / walk distance"
        case .healthSteps: return "Health · Steps"
        case .manualBinary: return "Manual · Yes / no"
        case .manualQuantity: return "Manual · Quantity"
        }
    }
    var defaultUnit: String {
        switch self {
        case .healthActiveEnergy: return "kcal"
        case .healthDistance: return "km"
        case .healthSteps: return "steps"
        case .manualBinary: return "day"
        case .manualQuantity: return "×"
        }
    }
    var defaultGoal: Double {
        switch self {
        case .healthActiveEnergy: return 500
        case .healthDistance: return 5
        case .healthSteps: return 9000
        case .manualBinary: return 1
        case .manualQuantity: return 8
        }
    }
}

struct Metric: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: MetricKind
    var unit: String
    var goal: Double            // normalization cap: t = min(1, value/goal-derived cap)
    var isArchived: Bool = false
}

/// One day of one metric. `day` is "yyyy-MM-dd" in the user's calendar.
struct DayValue: Codable, Hashable {
    var day: String
    var value: Double
}

// MARK: - Day math

enum Days {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        return f
    }()
    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date { formatter.date(from: key) ?? .now }
    static func lastKeys(_ n: Int, endingAt end: Date = .now) -> [String] {
        let cal = Calendar.current
        return (0..<n).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: end)).map(key)
        }
    }
}

// MARK: - Store

@Observable
final class MomentumStore {
    var metrics: [Metric] = []
    /// metricID → (dayKey → value)
    var values: [UUID: [String: Double]] = [:]
    var selectedMetricID: UUID?

    private var fileURL: URL { AppGroup.containerURL.appendingPathComponent("momentum.json") }

    struct Snapshot: Codable {
        var metrics: [Metric]
        var values: [UUID: [String: Double]]
        var selectedMetricID: UUID?
    }

    init() { load() }

    // MARK: persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            seedDefaults()
            return
        }
        metrics = snap.metrics
        values = snap.values
        selectedMetricID = snap.selectedMetricID ?? metrics.first?.id
    }

    func save() {
        let snap = Snapshot(metrics: metrics, values: values, selectedMetricID: selectedMetricID)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func seedDefaults() {
        let burn = Metric(name: "Burn", kind: .healthActiveEnergy, unit: "kcal", goal: 500)
        let sugar = Metric(name: "No sugar", kind: .manualBinary, unit: "day", goal: 1)
        metrics = [burn, sugar]
        selectedMetricID = burn.id
        seedSampleData(for: burn.id, style: .continuous(cap: 900))
        seedSampleData(for: sugar.id, style: .binary)
        save()
    }

    // MARK: reads

    var selectedMetric: Metric? { metrics.first { $0.id == selectedMetricID } ?? metrics.first }

    func value(_ metricID: UUID, on day: String) -> Double { values[metricID]?[day] ?? 0 }

    /// Last n days, oldest → newest, normalized against the metric's cap.
    func series(_ metric: Metric, days n: Int, endingAt end: Date = .now) -> [DayValue] {
        Days.lastKeys(n, endingAt: end).map { DayValue(day: $0, value: value(metric.id, on: $0)) }
    }

    /// Normalization cap: binary → 1; else 1.8× goal so "big days" still differentiate.
    func cap(for metric: Metric) -> Double {
        metric.kind == .manualBinary ? 1 : max(metric.goal * 1.8, 1)
    }

    func streak(_ metric: Metric, endingAt end: Date = .now) -> Int {
        var n = 0
        let cal = Calendar.current
        var d = cal.startOfDay(for: end)
        while value(metric.id, on: Days.key(d)) > 0 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return n
    }

    func total(_ metric: Metric, days n: Int) -> Double {
        series(metric, days: n).reduce(0) { $0 + $1.value }
    }

    // MARK: writes

    func set(_ metricID: UUID, day: String, value: Double) {
        values[metricID, default: [:]][day] = value
        save()
    }

    func toggleBinary(_ metricID: UUID, day: String) {
        let now = value(metricID, on: day)
        set(metricID, day: day, value: now > 0 ? 0 : 1)
    }

    func increment(_ metricID: UUID, day: String, by delta: Double) {
        set(metricID, day: day, value: max(0, value(metricID, on: day) + delta))
    }

    func add(_ metric: Metric) {
        metrics.append(metric)
        if selectedMetricID == nil { selectedMetricID = metric.id }
        save()
    }

    func archive(_ metric: Metric) {
        if let i = metrics.firstIndex(of: metric) { metrics[i].isArchived = true }
        save()
    }

    /// Bulk merge from HealthKit (dayKey → value).
    func mergeHealth(_ metricID: UUID, daily: [String: Double]) {
        for (k, v) in daily { values[metricID, default: [:]][k] = v }
        save()
    }

    // MARK: sample data (previews / simulator)

    enum SeedStyle { case continuous(cap: Double), binary }

    func seedSampleData(for metricID: UUID, style: SeedStyle, days n: Int = 365) {
        var rng = SeededRandom(seed: 7)
        let keys = Days.lastKeys(n)
        var prevActive = false
        for (i, key) in keys.enumerated() {
            let weekday = Calendar.current.component(.weekday, from: Days.date(key)) - 1
            var p = [0.2, 0.85, 0.7, 0.38, 0.8, 0.48, 0.88][weekday]
            if prevActive { p = min(0.95, p + 0.05) }
            if (60...66).contains(i % 120) { p *= 0.06 }   // occasional off-week
            let active = rng.next() < p
            prevActive = active
            guard active else { continue }
            switch style {
            case .continuous(let cap):
                var v = 170 + pow(rng.next(), 1.5) * (cap - 250)
                if rng.next() < 0.07 { v = v * 1.3 + 130 }
                values[metricID, default: [:]][key] = (v * 10).rounded() / 10
            case .binary:
                values[metricID, default: [:]][key] = 1
            }
        }
    }
}

/// Deterministic PRNG (mulberry32) so previews match the HTML canvas data feel.
struct SeededRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed &* 9973 &+ 11 }
    mutating func next() -> Double {
        state &+= 0x6D2B79F5
        var t = UInt64(state)
        t = (t ^ (t >> 15)) &* (1 | t)
        t ^= t &+ (t ^ (t >> 7)) &* (61 | t)
        return Double((t ^ (t >> 14)) & 0xFFFF_FFFF) / 4294967296
    }
}
