import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.grid.cross.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            StudioView()
                .tabItem { Label("Studio", systemImage: "square.grid.2x2") }
            MetricsView()
                .tabItem { Label("Metrics", systemImage: "slider.horizontal.3") }
        }
        .tint(Palette.greenDark.accent)
        .background(Chrome.background)
    }
}

#Preview {
    RootView()
        .environment(MomentumStore())
        .preferredColorScheme(.dark)
}
