import SwiftUI

/// History: backfill + insights.
/// Month pager (glass) → intensity calendar → insight blocks.
struct HistoryView: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monthOffset = 0          // 0 = current month
    @State private var editingDay: String?
    @State private var tapTick = 0

    private let cal = Calendar.current
    private var metric: Metric? { store.selectedMetric }

    private var monthAnchor: Date {
        cal.date(byAdding: .month, value: monthOffset,
                 to: cal.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let metric {
                        monthPager
                        weekdayRow
                        calendarGrid(metric)
                            .id(monthOffset)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        insights(metric)
                    }
                }
                .padding(20)
                .animation(Motion.respect(Motion.snap, reduceMotion: reduceMotion),
                           value: monthOffset)
            }
            .softTopEdge()
            .background(Chrome.background)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .light), trigger: tapTick)
            .sheet(item: $editingDay) { day in
                if let metric { QuantitySheet(metric: metric, day: day) }
            }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 34, weight: .heavy))
                .fontWidth(.expanded)
                .kerning(-0.8)
                .foregroundStyle(.white)
            Text(metric?.name ?? "")
                .widgetCaption(Chrome.tertiary)
        }
        .padding(.top, 8)
    }

    // MARK: month pager

    private var monthPager: some View {
        GlassGroup(spacing: 12) {
            HStack {
                pagerButton("chevron.left") { monthOffset -= 1 }
                Spacer()
                Text(monthAnchor, format: .dateTime.month(.wide).year())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Spacer()
                pagerButton("chevron.right") { monthOffset += 1 }
                    .disabled(monthOffset >= 0)
                    .opacity(monthOffset >= 0 ? 0.35 : 1)
            }
        }
    }

    private func pagerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            tapTick += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
        .glassCircle(interactive: true)
    }

    // MARK: calendar

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return HStack(spacing: 6) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Chrome.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarGrid(_ metric: Metric) -> some View {
        let days = monthDays()
        let cap = store.cap(for: metric)
        let todayStart = cal.startOfDay(for: .now)
        let palette = PresetStore.defaultLook().resolvedPalette()

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                         spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date, metric: metric, cap: cap,
                            todayStart: todayStart, palette: palette)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(_ date: Date, metric: Metric, cap: Double,
                         todayStart: Date, palette: Palette) -> some View {
        let key = Days.key(date)
        let value = store.value(metric.id, on: key)
        let future = date > todayStart
        let isToday = cal.isDate(date, inSameDayAs: .now)
        let t = min(1, value / cap)

        return Button {
            guard !future else { return }
            tapTick += 1
            if metric.kind == .manualBinary {
                withAnimation(Motion.respect(Motion.pop, reduceMotion: reduceMotion)) {
                    store.toggleBinary(metric.id, day: key)
                }
            } else if metric.kind == .manualQuantity {
                editingDay = key
            }
        } label: {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 13, weight: value > 0 ? .bold : .regular))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(value > 0 ? AnyShapeStyle(palette.ramp(t))
                                      : AnyShapeStyle(Chrome.card))
                .foregroundStyle(value > 0
                                 ? (palette.isDark ? Color(hex: "0C0D0F") : .white)
                                 : (future ? Chrome.tertiary.opacity(0.4) : .white))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(palette.accent, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.pressScale)
        .disabled(future || metric.kind.isHealth)
        .accessibilityLabel(Text(date, format: .dateTime.month().day()))
        .accessibilityValue(value > 0 ? "\(Int(value)) \(metric.unit)" : "empty")
    }

    /// Month days padded with leading nils to align the first weekday.
    private func monthDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: monthAnchor),
              let dayCount = cal.range(of: .day, in: .month, for: monthAnchor)?.count
        else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7
        let dates: [Date?] = (0..<dayCount).compactMap {
            cal.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: lead) + dates
    }

    // MARK: insights

    private func insights(_ metric: Metric) -> some View {
        let series = store.series(metric, days: 30)
        let best = series.max { $0.value < $1.value }
        return HStack(spacing: 12) {
            insight("Streak", "\(store.streak(metric))d")
            insight("Total · 30d", "\(Int(store.total(metric, days: 30)))")
            insight("Best day", best.flatMap { $0.value > 0 ? "\(Int($0.value))" : nil } ?? "—")
        }
    }

    private func insight(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabel()
            Text(value)
                .heroNumeral(22)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Chrome.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Chrome.hairline, lineWidth: 1)
        }
    }
}

/// Stepper sheet for quantity backfill — Liquid Glass controls on a material sheet.
struct QuantitySheet: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let metric: Metric
    let day: String

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(Chrome.hairline).frame(width: 36, height: 5).padding(.top, 8)
            Text(Days.date(day), format: .dateTime.weekday(.wide).month().day())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Chrome.secondary)
            GlassGroup(spacing: 24) {
                HStack(spacing: 24) {
                    step("minus") { store.increment(metric.id, day: day, by: -1) }
                    Text(store.value(metric.id, on: day),
                         format: .number.precision(.fractionLength(0)))
                        .heroNumeral(56)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .frame(minWidth: 120)
                    step("plus") { store.increment(metric.id, day: day, by: 1) }
                }
            }
            Text(metric.unit).widgetCaption(Chrome.tertiary)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .tint(Chrome.accent)
            .adaptiveGlassButton(prominent: true)
        }
        .padding(24)
        .presentationDetents([.height(340)])
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(28)
    }

    private func step(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.respect(Motion.pop, reduceMotion: reduceMotion)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
        }
        .glassCircle(interactive: true)
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
