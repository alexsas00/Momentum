import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Per-widget configuration intent (long-press → Edit Widget)

struct VizStyleOption: AppEntity {
    var id: String
    static let defaultQuery = VizStyleQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(VizStyle(rawValue: id)?.label ?? id)")
    }
}

struct VizStyleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [VizStyleOption] {
        identifiers.compactMap { VizStyle(rawValue: $0).map { VizStyleOption(id: $0.rawValue) } }
    }
    func suggestedEntities() async throws -> [VizStyleOption] {
        VizStyle.allCases.map { VizStyleOption(id: $0.rawValue) }
    }
    func defaultResult() async -> VizStyleOption? { VizStyleOption(id: VizStyle.burst.rawValue) }
}

struct PaletteOption: AppEntity {
    var id: String
    static let defaultQuery = PaletteQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Palette"
    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(Palette.curated.first { $0.id == id }?.name ?? "Custom")")
    }
}

struct PaletteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PaletteOption] {
        identifiers.map { PaletteOption(id: $0) }
    }
    func suggestedEntities() async throws -> [PaletteOption] {
        Palette.curated.map { PaletteOption(id: $0.id) } + [PaletteOption(id: "custom")]
    }
    func defaultResult() async -> PaletteOption? { PaletteOption(id: Palette.greenDark.id) }
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
        let store = MomentumStore()
        return store.metrics.filter { !$0.isArchived }.map {
            MetricOption(id: $0.id.uuidString, name: $0.name)
        }
    }
    func entities(for identifiers: [String]) async throws -> [MetricOption] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [MetricOption] { all() }
    func defaultResult() async -> MetricOption? { all().first }
}

struct MomentumWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Momentum Widget"
    static let description = IntentDescription("Choose metric, style and palette.")

    @Parameter(title: "Metric") var metric: MetricOption?
    @Parameter(title: "Style") var style: VizStyleOption?
    @Parameter(title: "Palette") var palette: PaletteOption?
}

// MARK: - Timeline

struct MomentumEntry: TimelineEntry {
    let date: Date
    let metric: Metric?
    let series: [DayValue]
    let palette: Palette
    let style: VizStyle
    let cap: Double
    let streak: Int
}

struct MomentumProvider: AppIntentTimelineProvider {
    func snapshot(for intent: MomentumWidgetIntent, in context: Context) async -> MomentumEntry {
        entry(for: intent, family: context.family)
    }
    func placeholder(in context: Context) -> MomentumEntry {
        entry(for: MomentumWidgetIntent(), family: context.family)
    }
    func timeline(for intent: MomentumWidgetIntent, in context: Context) async -> Timeline<MomentumEntry> {
        // Refresh at the next hour boundary; the app also force-reloads on every data write.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        return Timeline(entries: [entry(for: intent, family: context.family)], policy: .after(next))
    }

    private func entry(for intent: MomentumWidgetIntent, family: WidgetFamily) -> MomentumEntry {
        let store = MomentumStore()                  // reads shared App Group JSON
        let appConfig = WidgetConfig.load()          // Studio defaults

        let metric = intent.metric
            .flatMap { opt in store.metrics.first { $0.id.uuidString == opt.id } }
            ?? store.metrics.first { $0.id == appConfig.metricID }
            ?? store.selectedMetric

        var style = intent.style.flatMap { VizStyle(rawValue: $0.id) } ?? appConfig.style
        // Small-family fallback for styles that need width
        if family == .systemSmall && !style.supportsSmall { style = .burst }

        let palette: Palette
        if let pid = intent.palette?.id {
            palette = pid == "custom"
                ? appConfig.resolvedPalette()
                : (Palette.curated.first { $0.id == pid } ?? appConfig.resolvedPalette())
        } else {
            palette = appConfig.resolvedPalette()
        }

        let span = appConfig.span ?? style.defaultSpan
        let series = metric.map { store.series($0, days: span) } ?? []
        return MomentumEntry(
            date: .now,
            metric: metric,
            series: series,
            palette: palette,
            style: style,
            cap: metric.map { store.cap(for: $0) } ?? 1,
            streak: metric.map { store.streak($0) } ?? 0)
    }
}

// MARK: - Widget views

struct MomentumWidgetView: View {
    var entry: MomentumEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: standard
            }
        }
        .containerBackground(for: .widget) { entry.palette.widgetBackground }
    }

    private var input: VizInput {
        VizInput(series: entry.series, palette: entry.palette,
                 goal: entry.metric?.goal ?? 1, cap: entry.cap,
                 unit: entry.metric?.unit ?? "")
    }

    // Home screen: caption row + viz (mirrors canvas card anatomy)
    private var standard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if family != .systemSmall {
                HStack {
                    Text(entry.metric?.name ?? "Momentum")
                        .widgetCaption(entry.palette.secondaryText)
                    Spacer()
                    Text("\(entry.streak)d streak")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(entry.palette.accent)
                }
            }
            VizView(style: entry.style, input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Lock screen circular: goal gauge
    private var circular: some View {
        let today = entry.series.last?.value ?? 0
        let goal = max(entry.metric?.goal ?? 1, 0.001)
        return Gauge(value: min(1, today / goal)) {
            Text(entry.metric?.name.prefix(1).uppercased() ?? "M")
        } currentValueLabel: {
            Text("\(Int(today))").monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }

    // Lock screen inline: streak
    private var inline: some View {
        Text("\(entry.metric?.name ?? "Momentum") · \(entry.streak)d streak")
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
            .description("Your effort, eight ways.")
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
