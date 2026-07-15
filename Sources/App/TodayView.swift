import SwiftUI

/// Today: glance + log. Metric chips → hero viz card → quick-log controls.
struct TodayView: View {
    @Environment(MomentumStore.self) private var store
    @State private var config = WidgetConfig.load()

    private var metric: Metric? { store.selectedMetric }
    private var todayKey: String { Days.key(.now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    metricChips
                    if let metric {
                        heroCard(metric)
                        quickLog(metric)
                        statsRow(metric)
                    }
                }
                .padding(20)
            }
            .background(Chrome.background)
            .navigationTitle("Today")
            .refreshable { await HealthKitService.shared.syncAll(into: store) }
        }
    }

    // MARK: metric switcher — 44pt chips

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.metrics.filter { !$0.isArchived }) { m in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                            store.selectedMetricID = m.id
                            store.save()
                        }
                    } label: {
                        Text(m.name)
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(m.id == store.selectedMetricID ? Palette.greenDark.accent.opacity(0.16) : Chrome.card)
                            .foregroundStyle(m.id == store.selectedMetricID ? Palette.greenDark.accent : .white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: hero card — selected style at medium-widget proportions

    private func heroCard(_ metric: Metric) -> some View {
        let palette = config.resolvedPalette()
        let style = config.style
        let input = VizInput(
            series: store.series(metric, days: config.span ?? style.defaultSpan),
            palette: palette, goal: metric.goal,
            cap: store.cap(for: metric), unit: metric.unit)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(metric.name).widgetCaption(palette.secondaryText)
                Spacer()
                Text("\(Int(store.total(metric, days: 7))) \(metric.unit) / wk")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
            }
            VizView(style: style, input: input)
                .frame(height: 126)
                .animation(.spring(response: 0.35, dampingFraction: 1.0), value: store.value(metric.id, on: todayKey))
        }
        .padding(16)
        .background(palette.widgetBackground)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    // MARK: quick log

    @ViewBuilder
    private func quickLog(_ metric: Metric) -> some View {
        switch metric.kind {
        case .manualBinary:
            let done = store.value(metric.id, on: todayKey) > 0
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.toggleBinary(metric.id, day: todayKey)
                }
            } label: {
                Label(done ? "Done today" : "Mark today", systemImage: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(done ? Palette.greenDark.accent.opacity(0.16) : Chrome.card)
                    .foregroundStyle(done ? Palette.greenDark.accent : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

        case .manualQuantity:
            HStack(spacing: 16) {
                stepButton("minus") { store.increment(metric.id, day: todayKey, by: -1) }
                VStack(spacing: 2) {
                    Text(store.value(metric.id, on: todayKey), format: .number.precision(.fractionLength(0)))
                        .heroNumeral(40)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(metric.unit).widgetCaption(Chrome.tertiary)
                }
                .frame(maxWidth: .infinity)
                stepButton("plus") { store.increment(metric.id, day: todayKey, by: 1) }
            }
            .padding(16)
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))

        default:
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 12))
                Text("Synced from Health").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("pull to refresh").font(.system(size: 12)).foregroundStyle(Chrome.tertiary)
            }
            .foregroundStyle(Chrome.secondary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Chrome.card.opacity(0.6))
            .clipShape(Capsule())
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 54, height: 54)
                .background(Chrome.background)
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
    }

    // MARK: stats

    private func statsRow(_ metric: Metric) -> some View {
        HStack(spacing: 12) {
            stat("Streak", "\(store.streak(metric))", "days")
            stat("This week", "\(Int(store.total(metric, days: 7)))", metric.unit)
            stat("30 days", "\(Int(store.total(metric, days: 30)))", metric.unit)
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).widgetCaption(Chrome.tertiary)
            Text(value).heroNumeral(24).foregroundStyle(.white)
            Text(unit).font(.system(size: 11)).foregroundStyle(Chrome.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Chrome.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
