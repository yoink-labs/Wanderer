import SwiftUI

struct MainTabView: View {
    enum AppTab: Hashable {
        case trips, explore, profile
    }

    @State private var selection: AppTab = {
        switch DebugLaunch.tab {
        case "explore": return .explore
        case "profile": return .profile
        default: return .trips
        }
    }()

    var body: some View {
        TabView(selection: $selection) {
            TripsHomeView()
                .tabItem {
                    tabLabel("Trips", outline: "suitcase", filled: "suitcase.fill", tab: .trips)
                }
                .tag(AppTab.trips)

            ExploreView()
                .tabItem {
                    tabLabel("Explore", outline: "map", filled: "map.fill", tab: .explore)
                }
                .tag(AppTab.explore)

            ProfileView()
                .tabItem {
                    tabLabel("Profile", outline: "person.crop.circle", filled: "person.crop.circle.fill", tab: .profile)
                }
                .tag(AppTab.profile)
        }
        .tint(WandererTheme.controlTint)
        .sensoryFeedback(.selection, trigger: selection)
        // On a regular-width canvas (iPhone Duo open, iPad, Split View) the
        // system lays the tabs out as a vertical sidebar beside the content.
        // Compact width keeps the familiar bottom bar. No device checks.
        .tabViewStyle(.sidebarAdaptable)
    }

    /// Outline glyphs for unselected tabs, filled for the active one. The tab
    /// bar would otherwise force the filled variant on every item.
    private func tabLabel(_ title: String, outline: String, filled: String, tab: AppTab) -> some View {
        Label(title, systemImage: selection == tab ? filled : outline)
            .environment(\.symbolVariants, .none)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthStore())
}
