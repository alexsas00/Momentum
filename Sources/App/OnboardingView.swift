import SwiftUI

/// 3 pages: promise → Health permission → first metric. Skippable at any point.
struct OnboardingView: View {
    @Environment(MomentumStore.self) private var store
    var onDone: () -> Void
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            promise.tag(0)
            health.tag(1)
            firstMetric.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Chrome.background)
        .overlay(alignment: .topTrailing) {
            Button("Skip") { onDone() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Chrome.tertiary)
                .padding(24)
        }
    }

    private var promise: some View {
        VStack(spacing: 20) {
            Spacer()
            // Hero: burst viz with sample data
            if let m = store.metrics.first {
                VizView(style: .burst, input: VizInput(
                    series: store.series(m, days: 30),
                    palette: .greenDark, goal: m.goal,
                    cap: store.cap(for: m), unit: m.unit))
                .frame(width: 240, height: 240)
            }
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
            Spacer()
            next("Continue") { page = 1 }
        }
        .padding(24)
    }

    private var health: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.greenDark.accent)
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
            next("Allow Health access") {
                Task {
                    try? await HealthKitService.shared.requestAuthorization()
                    await HealthKitService.shared.syncAll(into: store)
                    page = 2
                }
            }
            Button("Not now") { page = 2 }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Chrome.tertiary)
        }
        .padding(24)
    }

    private var firstMetric: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Track anything")
                .font(.system(size: 28, weight: .heavy))
                .fontWidth(.expanded)
                .foregroundStyle(.white)
            Text("\"Day without sugar.\" \"Pages read.\" One tap a day — the chart does the rest. Add your first in Metrics.")
                .font(.system(size: 15))
                .foregroundStyle(Chrome.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            next("Start") { onDone() }
        }
        .padding(24)
    }

    private func next(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Palette.greenDark.accent)
                .foregroundStyle(Color(hex: "0C0D0F"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
