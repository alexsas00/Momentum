import SwiftUI

// MARK: - Shared preset rendering
//
// One renderer, three surfaces: the WidgetKit widget, the Today hero card, and
// every Studio preview/thumbnail. Guarantees what you design is what you place.
//
// ⚠️ Lives in Sources/App/Viz so it ships in BOTH targets (see project.yml).

/// Everything needed to draw one preset with real data.
struct PresetRenderData {
    var preset: WidgetPreset
    var metricName: String
    var streak: Int
    var input: VizInput

    var palette: Palette { preset.resolvedPalette() }
}

/// The inner content of a widget: optional caption row + visualization.
/// No background — the surface (widget container / app card) supplies it.
struct WidgetContentView: View {
    var data: PresetRenderData
    /// Small widgets drop the caption row to give the viz the full canvas.
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.preset.appearance.showsHeader && !isCompact {
                HStack(alignment: .firstTextBaseline) {
                    Text(data.metricName)
                        .widgetCaption(data.palette.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if data.preset.appearance.showsStreak {
                        Text("\(data.streak)d streak")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(data.palette.accent)
                    }
                }
            }
            VizView(style: data.preset.style, input: data.input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(data.metricName), \(data.preset.style.label) view, \(data.streak) day streak"))
    }
}

/// In-app card: content + appearance-driven background, radius, hairline.
/// Used for the Today hero, Studio live preview and preset thumbnails.
struct PresetCardView: View {
    var data: PresetRenderData
    var isCompact: Bool = false
    var showsShadow: Bool = false

    private var radius: CGFloat { data.preset.appearance.resolvedRadius(for: data.palette) }

    var body: some View {
        WidgetContentView(data: data, isCompact: isCompact)
            .padding(isCompact ? 12 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { cardBackground }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay { cardBorder }
            .shadow(color: showsShadow ? .black.opacity(0.35) : .clear, radius: 24, y: 10)
    }

    @ViewBuilder private var cardBackground: some View {
        switch data.preset.appearance.background {
        case .palette: data.palette.widgetBackground
        case .gradient: data.palette.backgroundGradient
        case .black: Color.black
        case .transparent: Color.clear
        }
    }

    @ViewBuilder private var cardBorder: some View {
        if data.preset.appearance.background == .transparent {
            // Previews only: signal "this floats on your wallpaper".
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .foregroundStyle(Chrome.hairline)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Chrome.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Data assembly

extension PresetRenderData {
    /// Build render data for a preset from the store, resolving its metric
    /// (or falling back to the currently selected one).
    @MainActor
    static func make(preset: WidgetPreset, store: MomentumStore) -> PresetRenderData {
        let metric = preset.metricID.flatMap { id in store.metrics.first { $0.id == id } }
            ?? store.selectedMetric
        let input: VizInput
        let streak: Int
        if let metric {
            input = VizInput(
                series: store.series(metric, days: preset.resolvedSpan()),
                palette: preset.resolvedPalette(),
                goal: metric.goal,
                cap: store.cap(for: metric),
                unit: metric.unit)
            streak = store.streak(metric)
        } else {
            input = VizInput(series: [], palette: preset.resolvedPalette(),
                             goal: 1, cap: 1, unit: "")
            streak = 0
        }
        return PresetRenderData(
            preset: preset,
            metricName: metric?.name ?? "Momentum",
            streak: streak,
            input: input)
    }
}
