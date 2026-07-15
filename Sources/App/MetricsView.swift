import SwiftUI

/// Metrics manager: list, add sheet, swipe-to-archive.
struct MetricsView: View {
    @Environment(MomentumStore.self) private var store
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.metrics.filter { !$0.isArchived }) { m in
                        row(m)
                            .listRowBackground(Chrome.card)
                            .listRowSeparatorTint(Chrome.hairline)
                            .swipeActions {
                                Button("Archive", role: .destructive) {
                                    withAnimation(Motion.settle) { store.archive(m) }
                                }
                            }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Metrics")
                            .font(.system(size: 34, weight: .heavy))
                            .fontWidth(.expanded)
                            .kerning(-0.8)
                            .foregroundStyle(.white)
                        Text("What Momentum draws")
                            .widgetCaption(Chrome.tertiary)
                    }
                    .textCase(nil)
                    .padding(.bottom, 12)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Chrome.background)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(isPresented: $showingAdd) { AddMetricSheet() }
        }
    }

    private func row(_ m: Metric) -> some View {
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
            if m.kind.isHealth {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .glassCircle(tint: Chrome.accent.opacity(0.3), interactive: true)
        .padding(20)
        .accessibilityLabel("Add metric")
    }
}

/// Add-metric sheet: name → kind chips → goal, one screen, no friction.
struct AddMetricSheet: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: MetricKind = .manualBinary
    @State private var goal: Double = MetricKind.manualBinary.defaultGoal
    @State private var unit = MetricKind.manualBinary.defaultUnit
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Capsule().fill(Chrome.hairline).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).padding(.top, 8)

            Text("New metric")
                .font(.system(size: 24, weight: .heavy))
                .fontWidth(.expanded)
                .foregroundStyle(.white)

            // Name
            TextField("Name — e.g. No sugar", text: $name)
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Chrome.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.done)

            // Kind
            VStack(alignment: .leading, spacing: 10) {
                Text("Source").sectionLabel()
                VStack(spacing: 8) {
                    ForEach(MetricKind.allCases) { k in
                        kindRow(k)
                    }
                }
            }

            // Goal
            HStack {
                Text("Daily goal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(goal)) \(unit)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Chrome.accent)
                Stepper("", value: $goal, in: 1...20000, step: kind == .healthSteps ? 500 : 1)
                    .labelsHidden()
                    .disabled(kind == .manualBinary)
                    .opacity(kind == .manualBinary ? 0.4 : 1)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)

            Button {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                store.add(Metric(name: trimmed.isEmpty ? kind.label : trimmed,
                                 kind: kind, unit: unit, goal: goal))
                dismiss()
            } label: {
                Text("Add metric")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .tint(Chrome.accent)
            .adaptiveGlassButton(prominent: true)
        }
        .padding(24)
        .presentationDetents([.large])
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(28)
        .onChange(of: kind) { _, new in
            goal = new.defaultGoal
            unit = new.defaultUnit
        }
        .onAppear { nameFocused = true }
    }

    private func kindRow(_ k: MetricKind) -> some View {
        let selected = kind == k
        return Button {
            kind = k
        } label: {
            HStack {
                Text(k.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Chrome.accent : .white)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Chrome.accent : Chrome.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(selected ? Chrome.accent.opacity(0.10) : Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Chrome.accent.opacity(0.5) : Chrome.hairline,
                                  lineWidth: 1)
            }
        }
        .buttonStyle(.pressScale)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
