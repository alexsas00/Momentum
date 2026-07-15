import SwiftUI

struct RootView: View {
    var body: some View {
        tabs
            .tint(Chrome.accent)
            .background(Chrome.background)
    }

    // On iOS 26 the tab bar is Liquid Glass automatically (built with the 26 SDK);
    // we additionally let it recede while scrolling for a calmer canvas.
    @ViewBuilder private var tabs: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            baseTabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            baseTabs
        }
        #else
        baseTabs
        #endif
    }

    private var baseTabs: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.grid.cross.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            StudioView()
                .tabItem { Label("Studio", systemImage: "square.grid.2x2.fill") }
            MetricsView()
                .tabItem { Label("Metrics", systemImage: "slider.horizontal.3") }
        }
    }
}

#Preview {
    RootView()
        .environment(MomentumStore())
        .preferredColorScheme(.dark)
}
