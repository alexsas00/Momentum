import SwiftUI

/// Today: glance + log.
/// Anatomy: Momentum wordmark header → metric chips (glass) → hero viz card →
/// quick-log (glass controls) → stat blocks.
struct TodayView: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var config = WidgetConfig.load()
    @State private var logTick = 0   // haptic trigger

    private var metric: Metric? { store.selectedMetric }
    private var todayKey: String { Days.key(.now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    metricChips
                    if let metric {
                        heroCard(metric)
                            .id(metric.id)   // card swaps, not mutates, on metric change
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                removal: .opacity))
                        quickLog(metric)
                        statsRow(metric)
                    }
                }
                .padding(20)
                .animation(Motion.respect(Motion.settle, reduceMotion: reduceMotion),
                           value: store.selectedMetricID)
            }
            .softTopEdge()
            .background(Chrome.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await HealthKitService.shared.syncAll(into: store) }
            .sensoryFeedback(.impact(weight: .light), trigger: logTick)
        }
    }

    // MARK: header — the wordmark

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Momentum")
                    .wordmark(40)
                    .foregroundStyle(.white)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .widgetCaption(Chrome.tertiary)
            }
            Spacer()
            if let metric, store.streak(metric) > 0 {
                streakBadge(store.streak(metric))
            }
        }
        .padding(.top, 8)
    }

    private func streakBadge(_ days: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill").font(.system(size: 12, weight: .semibold))
            Text("\(days)")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(Chrome.accent)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassCapsule(tint: Chrome.accent.opacity(0.25))
    }

    // MARK: metric switcher — glass chips

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(store.metrics.filter { !$0.isArchived }) { m in
                        let selected = m.id == store.selectedMetricID
                        Button {
                            withAnimation(Motion.respect(Motion.snap, reduceMotion: reduceMotion)) {
                                store.selectedMetricID = m.id
                                store.save()
                            }
                        } label: {
                            Text(m.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selected ? Chrome.accent : .white)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                        }
                        .glassCapsule(tint: selected ? Chrome.accent.opacity(0.3) : nil,
                                      interactive: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
    }

    // MARK: hero card — the widget, mirrored in-app

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
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.accent)
            }
            VizView(style: style, input: input)
                .frame(height: 126)
                .animation(Motion.respect(Motion.settle, reduceMotion: reduceMotion),
                           value: store.value(metric.id, on: todayKey))
        }
        .padding(16)
        .background(palette.widgetBackground)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .strokeBorder(Chrome.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    // MARK: quick log — glass controls

    @ViewBuilder
    private func quickLog(_ metric: Metric) -> some View {
        switch metric.kind {
        case .manualBinary:
            let done = store.value(metric.id, on: todayKey) > 0
            Button {
                logTick += 1
                withAnimation(Motion.respect(Motion.pop, reduceMotion: reduceMotion)) {
                    store.toggleBinary(metric.id, day: todayKey)
                }
            } label: {
                Label(done ? "Done today" : "Mark today",
                      systemImage: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .tint(done ? Chrome.accent : nil)
            .adaptiveGlassButton(prominent: done)

        case .manualQuantity:
            GlassGroup(spacing: 16) {
                HStack(spacing: 16) {
                    stepButton("minus") { store.increment(metric.id, day: todayKey, by: -1) }
                    VStack(spacing: 2) {
                        Text(store.value(metric.id, on: todayKey),
                             format: .number.precision(.fractionLength(0)))
                            .heroNumeral(40)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(metric.unit).widgetCaption(Chrome.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    stepButton("plus") { store.increment(metric.id, day: todayKey, by: 1) }
                }
                .padding(12)
            }
            .background(Chrome.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Chrome.hairline, lineWidth: 1)
            }

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
            .glassCapsule()
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            logTick += 1
            withAnimation(Motion.respect(Motion.pop, reduceMotion: reduceMotion)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
        }
        .glassCircle(interactive: true)
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
            Text(label).sectionLabel()
            Text(value)
                .heroNumeral(24)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(unit).font(.system(size: 11)).foregroundStyle(Chrome.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Chrome.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(Chrome.hairline, lineWidth: 1)
        }
    }
}
