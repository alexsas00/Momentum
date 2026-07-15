import SwiftUI

/// History: month calendar with intensity-tinted cells; tap a past day to backfill.
struct HistoryView: View {
    @Environment(MomentumStore.self) private var store
    @State private var monthOffset = 0
    @State private var editingDay: String?

    private var metric: Metric? { store.selectedMetric }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let metric {
                        monthHeader
                        calendarGrid(metric)
                        insights(metric)
                    }
                }
                .padding(20)
            }
            .background(Chrome.background)
            .navigationTitle("History")
            .sheet(item: $editingDay) { day in
                if let metric { QuantitySheet(metric: metric, day: day) }
            }
        }
    }

    private var month: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: .now) ?? .now
    }

    private var monthHeader: some View {
        HStack {
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 1)) { monthOffset -= 1 } } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 1)) { monthOffset += 1 } } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(monthOffset >= 0)
        }
        .foregroundStyle(.white)
    }

    // MARK: calendar

    private func calendarGrid(_ metric: Metric) -> some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        let first = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: first)!.count
        let leadingBlanks = cal.component(.weekday, from: first) - 1
        let todayStart = cal.startOfDay(for: .now)
        let cap = store.cap(for: metric)

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { d in
                Text(d).font(.system(size: 10, weight: .semibold)).foregroundStyle(Chrome.tertiary)
            }
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 40) }
            ForEach(1...daysInMonth, id: \.self) { dayNum in
                let date = cal.date(byAdding: .day, value: dayNum - 1, to: first)!
                let key = Days.key(date)
                let value = store.value(metric.id, on: key)
                let future = date > todayStart
                let t = min(1, value / cap)

                Button {
                    guard !future else { return }
                    if metric.kind == .manualBinary {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.toggleBinary(metric.id, day: key)
                        }
                    } else if metric.kind == .manualQuantity {
                        editingDay = key
                    }
                } label: {
                    Text("\(dayNum)")
                        .font(.system(size: 13, weight: value > 0 ? .bold : .regular))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(value > 0 ? Palette.greenDark.ramp(t) : Chrome.card)
                        .foregroundStyle(value > 0 ? Color(hex: "0C0D0F") : (future ? Chrome.tertiary.opacity(0.4) : .white))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if cal.isDate(date, inSameDayAs: .now) {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Palette.greenDark.accent, lineWidth: 1.5)
                            }
                        }
                }
                .disabled(future || metric.kind.isHealth)
            }
        }
    }

    // MARK: insights

    private func insights(_ metric: Metric) -> some View {
        let series = store.series(metric, days: 30)
        let best = series.max { $0.value < $1.value }
        return HStack(spacing: 12) {
            insight("Streak", "\(store.streak(metric))d")
            insight("Total · 30d", "\(Int(store.total(metric, days: 30)))")
            insight("Best day", best.map { "\(Int($0.value))" } ?? "—")
        }
    }

    private func insight(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).widgetCaption(Chrome.tertiary)
            Text(value).heroNumeral(22).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Chrome.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Stepper sheet for quantity backfill.
struct QuantitySheet: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let metric: Metric
    let day: String

    var body: some View {
        VStack(spacing: 24) {
            Text(Days.date(day), format: .dateTime.weekday(.wide).month().day())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Chrome.secondary)
            HStack(spacing: 24) {
                step("minus") { store.increment(metric.id, day: day, by: -1) }
                Text(store.value(metric.id, on: day), format: .number.precision(.fractionLength(0)))
                    .heroNumeral(56)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(minWidth: 120)
                step("plus") { store.increment(metric.id, day: day, by: 1) }
            }
            Text(metric.unit).widgetCaption(Chrome.tertiary)
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Palette.greenDark.accent.opacity(0.16))
                .foregroundStyle(Palette.greenDark.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(24)
        .presentationDetents([.height(320)])
        .presentationBackground(Chrome.card)
    }

    private func step(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 60, height: 60)
                .background(Chrome.background)
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
