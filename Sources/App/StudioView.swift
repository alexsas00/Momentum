import SwiftUI
import WidgetKit

/// Widget Studio: live preview + style gallery + palette row + metric/span pickers.
/// Writes WidgetConfig to the App Group and reloads timelines, so placed widgets follow.
struct StudioView: View {
    @Environment(MomentumStore.self) private var store
    @State private var config = WidgetConfig.load()
    @State private var customColor: Color = Palette.greenDark.accent
    @State private var previewFamily: PreviewFamily = .medium

    enum PreviewFamily: String, CaseIterable { case small = "Small", medium = "Medium" }

    private var metric: Metric? {
        store.metrics.first { $0.id == config.metricID } ?? store.selectedMetric
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    preview
                    sizePicker
                    styleGallery
                    paletteRow
                    metricAndSpan
                }
                .padding(20)
            }
            .background(Chrome.background)
            .navigationTitle("Studio")
            .onChange(of: config) { _, new in
                new.save()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: live preview

    private var preview: some View {
        let palette = config.resolvedPalette()
        return HStack {
            Spacer()
            if let metric {
                let input = VizInput(
                    series: store.series(metric, days: config.span ?? config.style.defaultSpan),
                    palette: palette, goal: metric.goal,
                    cap: store.cap(for: metric), unit: metric.unit)
                VizView(style: config.style, input: input)
                    .padding(16)
                    .frame(
                        width: previewFamily == .small ? 158 : 344,
                        height: 158)
                    .background(palette.widgetBackground)
                    .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                    .animation(.spring(response: 0.35, dampingFraction: 1), value: config)
            }
            Spacer()
        }
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(hex: "131418"))) // wallpaper well
    }

    private var sizePicker: some View {
        Picker("Size", selection: $previewFamily) {
            ForEach(PreviewFamily.allCases, id: \.self) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: style gallery — mini-previews

    private var styleGallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style").widgetCaption(Chrome.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(VizStyle.allCases) { style in
                        let selected = style == config.style
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 1)) { config.style = style }
                        } label: {
                            VStack(spacing: 6) {
                                if let metric {
                                    VizView(style: style, input: VizInput(
                                        series: store.series(metric, days: style.defaultSpan),
                                        palette: config.resolvedPalette(), goal: metric.goal,
                                        cap: store.cap(for: metric), unit: metric.unit))
                                    .allowsHitTesting(false)
                                    .frame(width: 92, height: 64)
                                    .scaleEffect(0.85)
                                    .clipped()
                                }
                                Text(style.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selected ? Palette.greenDark.accent : Chrome.secondary)
                            }
                            .padding(10)
                            .background(Chrome.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Palette.greenDark.accent, lineWidth: 1.5)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: palettes — curated swatches + custom picker

    private var paletteRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Palette").widgetCaption(Chrome.tertiary)
            HStack(spacing: 12) {
                ForEach(Palette.curated) { p in
                    let selected = config.paletteID == p.id
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 1)) { config.paletteID = p.id }
                    } label: {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: p.rampLowHex), Color(hex: p.rampHighHex)],
                                startPoint: .bottomLeading, endPoint: .topTrailing))
                            .frame(width: 36, height: 36)
                            .overlay {
                                if let red = p.interrupt {
                                    Circle().fill(red).frame(width: 8, height: 8).offset(x: 10, y: -10)
                                }
                            }
                            .overlay {
                                Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0.12), lineWidth: selected ? 2 : 1)
                            }
                    }
                    .accessibilityLabel(p.name)
                }
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 36)
                    .onChange(of: customColor) { _, new in
                        config.paletteID = "custom"
                        config.customAccentHex = UIColor(new).hexString
                    }
            }
        }
    }

    // MARK: metric + span

    private var metricAndSpan: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Metric").widgetCaption(Chrome.tertiary)
                Picker("Metric", selection: Binding(
                    get: { metric?.id ?? UUID() },
                    set: { config.metricID = $0 })) {
                    ForEach(store.metrics.filter { !$0.isArchived }) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.greenDark.accent)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Time span").widgetCaption(Chrome.tertiary)
                Picker("Span", selection: Binding(
                    get: { config.span ?? config.style.defaultSpan },
                    set: { config.span = $0 })) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("24 weeks").tag(168)
                    Text("Year").tag(365)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
