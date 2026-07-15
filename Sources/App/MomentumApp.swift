import SwiftUI

@main
struct MomentumApp: App {
    @State private var store = MomentumStore()
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some Scene {
        WindowGroup {
            Group {
                if didOnboard {
                    RootView()
                } else {
                    OnboardingView { didOnboard = true }
                }
            }
            .environment(store)
            .preferredColorScheme(.dark)
            .task {
                await HealthKitService.shared.syncAll(into: store, days: 365)
            }
        }
    }
}
