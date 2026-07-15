import SwiftUI

/// Onboarding — three pages, thirty seconds, zero friction.
/// 1. Promise (animated burst)  2. Health permission  3. Quick-start metrics.
struct OnboardingView: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDone: () -> Void

    @State private var page = 0
    @State private var heroVisible = false
    @State private var queued: Set<String> = ["Burn"]   // pre-checked template names

    private let templates: [(name: String, kind: MetricKind, goal: Double, unit: String)] = [
        ("Burn", .healthActiveEnergy, 500, "kcal"),
        ("Steps", .healthSteps, 9000, "steps"),
        ("No sugar", .manualBinary, 1, "day"),
        ("Water", .manualQuantity, 8, "glasses"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                promise.tag(0)
                health.tag(1)
                firstMetrics.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots
            cta
        }
        .background(Chrome.background)
        .overlay(alignment: .topTrailing) {
            Button("Skip") { onDone() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Chrome.tertiary)
                .padding(24)
                .opacity(page == 2 ? 0 : 1)
        }
        .animation(Motion.respect(Motion.snap, reduceMotion: reduceMotion), value: page)
    }

    // MARK: page 1 — promise

    private var promise: some View {
        VStack(spacing: 24) {
            Spacer()
            if let m = store.metrics.first {
                VizView(style: .burst, input: VizInput(
                    series: store.series(m, days: 30),
                    palette: .greenDark, goal: m.goal,
                    cap: store.cap(for: m), unit: m.unit))
                .frame(width: 240, height: 240)
                .scaleEffect(heroVisible ? 1 : 0.85)
                .opacity(heroVisible ? 1 : 0)
                .onAppear {
                    withAnimation(Motion.respect(
                        .spring(response: 0.6, dampingFraction: 0.8),
                        reduceMotion: reduceMotion)) { heroVisible = true }
                }
            }
            VStack(spacing: 12) {
                Text("Momentum")
                    .wordmark(24)
                    .foregroundStyle(Chrome.accent)
                Text("Your effort,\non your home screen")
                    .font(.system(size: 32, weight: .heavy))
                    .fontWidth(.expanded)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("Eight ways to see a month of work at a glance — calories, kilometers, or any habit you invent.")
                    .font(.system(size: 15))
                    .foregroundStyle(Chrome.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: page 2 — health

    private var health: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(Chrome.accent)
                .frame(width: 96, height: 96)
                .glassCircle(tint: Chrome.accent.opacity(0.2), interactive: false)
            Text("Connect Health")
                .font(.system(size: 28, weight: .heavy))
                .fontWidth(.expanded)
                .foregroundStyle(.white)
            Text("Momentum reads energy burned, distance and steps. Nothing is written back, nothing leaves your device.")
                .font(.system(size: 15))
                .foregroundStyle(Chrome.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(24)
    }

    // MARK: page 3 — quick start

    private var firstMetrics: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Start tracking")
                .font(.system(size: 28, weight: .heavy))
                .fontWidth(.expanded)
                .foregroundStyle(.white)
            Text("Pick what to draw. You can add anything later.")
                .font(.system(size: 15))
                .foregroundStyle(Chrome.secondary)

            VStack(spacing: 10) {
                ForEach(templates, id: \.name) { t in
                    templateRow(t)
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private func templateRow(_ t: (name: String, kind: MetricKind, goal: Double, unit: String)) -> some View {
        let on = queued.contains(t.name)
        return Button {
            withAnimation(Motion.respect(Motion.pop, reduceMotion: reduceMotion)) {
                if on { queued.remove(t.name) } else { queued.insert(t.name) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(on ? Chrome.accent : .white)
                    Text(t.kind.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.tertiary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Chrome.accent : Chrome.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(on ? Chrome.accent.opacity(0.10) : Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(on ? Chrome.accent.opacity(0.5) : Chrome.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.pressScale)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: chrome

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Chrome.accent : Chrome.hairline)
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
        .padding(.bottom, 20)
        .accessibilityHidden(true)
    }

    private var cta: some View {
        Button {
            switch page {
            case 0:
                page = 1
            case 1:
                Task {
                    // Ask for read access, pull the first sync, then move on.
                    await HealthKitService.shared.syncAll(into: store)
                    page = 2
                }
            default:
                for t in templates where queued.contains(t.name) {
                    guard !store.metrics.contains(where: { $0.name == t.name }) else { continue }
                    store.add(Metric(name: t.name, kind: t.kind, unit: t.unit, goal: t.goal))
                }
                onDone()
            }
        } label: {
            Text(page == 0 ? "Continue" : page == 1 ? "Allow Health access" : "Start")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .contentTransition(.opacity)
        }
        .tint(Chrome.accent)
        .adaptiveGlassButton(prominent: true)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}
