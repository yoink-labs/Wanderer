import SwiftUI
import UIKit

@main
struct WandererApp: App {
    @StateObject private var auth = AuthStore()

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(WandererTheme.platinum)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(WandererTheme.charcoal)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(WandererTheme.charcoal)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .preferredColorScheme(.light)
        }
    }
}
