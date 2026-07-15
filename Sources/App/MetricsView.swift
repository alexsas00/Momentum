import SwiftUI

/// Metrics manager: list, add sheet, swipe-to-archive.
struct MetricsView: View {
    @Environment(MomentumStore.self) private var store
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.metrics.filter { !$0.isArchived }) { m in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.name).font(.system(size: 16, weight: .semibold))
                            Text(m.kind.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Chrome.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Int(m.goal))")
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                            Text("\(m.unit) / day")
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.tertiary)
                        }
                    }
                    .listRowBackground(Chrome.card)
                    .swipeActions {
                        Button("Archive", role: .destructive) { store.archive(m) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Chrome.background)
            .navigationTitle("Metrics")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .tint(Palette.greenDark.accent)
            }
            .sheet(isPresented: $showingAdd) { AddMetricSheet() }
        }
    }
}

struct AddMetricSheet: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: MetricKind = .manualBinary
    @State private var goal: Double = 1
    @State private var unit = "day"

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. No sugar, Run, Pages read", text: $name)
                }
                Section("Source") {
                    Picker("Kind", selection: $kind) {
                        ForEach(MetricKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    .onChange(of: kind) { _, new in
                        goal = new.defaultGoal
                        unit = new.defaultUnit
                    }
                }
                if kind != .manualBinary {
                    Section("Daily goal") {
                        HStack {
                            TextField("Goal", value: $goal, format: .number)
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                            TextField("Unit", text: $unit)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Chrome.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Chrome.background)
            .navigationTitle("New metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(Metric(name: name, kind: kind, unit: unit, goal: goal))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .tint(Palette.greenDark.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
