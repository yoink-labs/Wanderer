import ClerkKit
import SwiftUI
import UIKit

@main
struct WandererApp: App {
    @StateObject private var auth = AuthStore()
    @AppStorage("wanderer.appearance") private var appearanceRaw = WandererAppearance.system.rawValue

    private var appearance: WandererAppearance {
        WandererAppearance(rawValue: appearanceRaw) ?? .system
    }

    init() {
        if let key = CloudConfiguration.clerkPublishableKey, !key.isEmpty {
            Clerk.configure(publishableKey: key)
        }
        Self.configureBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// UIKit bars need an explicit appearance because the app draws its own
    /// navigation chrome. Both colours resolve per trait, so the bars follow
    /// light/dark without being rebuilt.
    private static func configureBars() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = .adaptive(light: 0xEFF1F3, dark: 0x0E1417)
        let title = UIColor.adaptive(light: 0x223843, dark: 0xECF1F3)
        navigation.titleTextAttributes = [.foregroundColor: title]
        navigation.largeTitleTextAttributes = [.foregroundColor: title]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = navigation
        bar.scrollEdgeAppearance = navigation
        bar.compactAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = .adaptive(light: 0xEFF1F3, dark: 0x0E1417)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
