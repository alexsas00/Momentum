import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Per-widget configuration (long-press → Edit Widget)
//
// The headline parameter is **Design**: any preset saved in the Studio.
// Every placed widget instance picks its own design independently, so five
// Momentum widgets can show five different saved looks at once.
// An optional **Metric** override reuses one design across habits.

struct DesignOption: AppEntity {
    var id: String            // WidgetPreset.id.uuidString
    var name: String
    var detail: String        // "Burst · Ember"

    static let defaultQuery = DesignQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Design"
    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)", subtitle: "\(detail)")
    }

    static func from(_ preset: WidgetPreset) -> DesignOption {
        DesignOption(id: preset.id.uuidString,
                     name: preset.name,
                     detail: "\(preset.style.label) · \(preset.resolvedPalette().name)")
    }
}

struct DesignQuery: EntityQuery {
    private func all() -> [DesignOption] { PresetStore.load().map(DesignOption.from) }

    func entities(for identifiers: [String]) async throws -> [DesignOption] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [DesignOption] { all() }
    func defaultResult() async -> DesignOption? {
        PresetStore.defaultPresetID
            .flatMap { PresetStore.preset(id: $0) }
            .map(DesignOption.from) ?? all().first
    }
}

struct MetricOption: AppEntity {
    var id: String
    var name: String
    static let defaultQuery = MetricQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}

struct MetricQuery: EntityQuery {
    private func all() -> [MetricOption] {
        MomentumStore().metrics.filter { !$0.isArchived }
            .map { MetricOption(id: $0.id.uuidString, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [MetricOption] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [MetricOption] { all() }
    func defaultResult() async -> MetricOption? { nil }   // nil = follow the design
}

struct MomentumWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Momentum"
    static let description = IntentDescription(
        "Pick one of your saved designs. Each widget can show a different one.")

    @Parameter(title: "Design") var design: DesignOption?
    @Parameter(title: "Metric", description: "Override the design's metric")
    var metric: MetricOption?
}

// MARK: - Timeline

struct MomentumEntry: TimelineEntry {
    let date: Date
    let data: PresetRenderData
    let goalToday: Double        // today's value vs goal (lock screen gauge)
    let goal: Double
    let total7: Double           // large-family footer
    let total30: Double
}

struct MomentumProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MomentumEntry {
        entry(for: MomentumWidgetIntent(), family: context.family)
    }
    func snapshot(for intent: MomentumWidgetIntent, in context: Context) async -> MomentumEntry {
        entry(for: intent, family: context.family)
    }
    func timeline(for intent: MomentumWidgetIntent, in context: Context) async -> Timeline<MomentumEntry> {
        // Data changes only on user action or Health sync; the app force-reloads
        // on every write. Hourly boundary keeps "today" fresh across midnight.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        return Timeline(entries: [entry(for: intent, family: context.family)], policy: .after(next))
    }

    private func entry(for intent: MomentumWidgetIntent, family: WidgetFamily) -> MomentumEntry {
        let store = MomentumStore()   // reads shared App Group JSON

        // 1. Design: this instance's chosen preset, else the Studio default.
        var preset = intent.design
            .flatMap { UUID(uuidString: $0.id) }
            .flatMap { PresetStore.preset(id: $0) }
            ?? PresetStore.defaultLook()

        // 2. Optional metric override on top of the design.
        if let override = intent.metric.flatMap({ UUID(uuidString: $0.id) }) {
            preset.metricID = override
        }

        // 3. Small-family fallback for styles that need width.
        if family == .systemSmall && !preset.style.supportsSmall { preset.style = .burst }

        let metric = preset.metricID.flatMap { id in store.metrics.first { $0.id == id } }
            ?? store.selectedMetric

        let input: VizInput
        let streak: Int
        if let metric {
            input = VizInput(series: store.series(metric, days: preset.resolvedSpan()),
                             palette: preset.resolvedPalette(), goal: metric.goal,
                             cap: store.cap(for: metric), unit: metric.unit)
            streak = store.streak(metric)
        } else {
            input = VizInput(series: [], palette: preset.resolvedPalette(),
                             goal: 1, cap: 1, unit: "")
            streak = 0
        }

        return MomentumEntry(
            date: .now,
            data: PresetRenderData(preset: preset,
                                   metricName: metric?.name ?? "Momentum",
                                   streak: streak,
                                   input: input),
            goalToday: metric.map { store.value($0.id, on: Days.key(.now)) } ?? 0,
            goal: max(metric?.goal ?? 1, 0.001),
            total7: metric.map { store.total($0, days: 7) } ?? 0,
            total30: metric.map { store.total($0, days: 30) } ?? 0)
    }
}

// MARK: - Widget views

struct MomentumWidgetView: View {
    var entry: MomentumEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var palette: Palette { entry.data.palette }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .systemLarge: large
            default: standard
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    /// Appearance-driven surface. In accented/vibrant rendering the system
    /// re-maps content into the material, so we hand it a neutral canvas.
    @ViewBuilder private var widgetBackground: some View {
        if renderingMode != .fullColor {
            Color.clear
        } else {
            switch entry.data.preset.appearance.background {
            case .palette: palette.widgetBackground
            case .gradient: palette.backgroundGradient
            case .black: Color.black
            case .transparent: Color.clear
            }
        }
    }

    // Home screen small/medium: shared content, caption row accent-aware.
    private var standard: some View {
        WidgetContentView(data: entry.data, isCompact: family == .systemSmall)
            .widgetAccentable(entry.data.preset.appearance.showsHeader)
    }

    // Large: content + a quiet stats footer.
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetContentView(data: entry.data)
            HStack(spacing: 0) {
                footerStat("Streak", "\(entry.data.streak)d")
                footerStat("7 days", "\(Int(entry.total7))")
                footerStat("30 days", "\(Int(entry.total30))")
            }
            .padding(.top, 2)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.primaryText.opacity(0.08)).frame(height: 1)
            }
        }
    }

    private func footerStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).widgetCaption(palette.tertiaryText)
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .fontWidth(.expanded)
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Lock screen circular: goal gauge.
    private var circular: some View {
        Gauge(value: min(1, entry.goalToday / entry.goal)) {
            Text(entry.data.metricName.prefix(1).uppercased())
        } currentValueLabel: {
            Text("\(Int(entry.goalToday))").monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }

    // Lock screen inline: streak.
    private var inline: some View {
        Text("\(entry.data.metricName) · \(entry.data.streak)d streak")
    }
}

// MARK: - Widget declaration

struct MomentumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "MomentumWidget",
            intent: MomentumWidgetIntent.self,
            provider: MomentumProvider()) { entry in
                MomentumWidgetView(entry: entry)
            }
            .configurationDisplayName("Momentum")
            .description("Your saved designs, on your Home Screen.")
            .supportedFamilies([
                .systemSmall, .systemMedium, .systemLarge,
                .accessoryCircular, .accessoryInline,
            ])
    }
}

@main
struct MomentumWidgets: WidgetBundle {
    var body: some Widget {
        MomentumWidget()
    }
}
