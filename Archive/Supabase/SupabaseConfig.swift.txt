import Foundation

/// Supabase client configuration, read from the build's Info.plist.
///
/// Values come from `Config/Supabase.local.xcconfig`, which is gitignored. Only
/// the project URL and publishable key belong there: the publishable key ships
/// inside every app and is constrained by row-level security. The database
/// password and service-role/secret key must never appear here.
enum SupabaseConfig {
    static let url = URL(string: infoValue("SupabaseURL")) ?? URL(string: "http://127.0.0.1:54321")!
    static let publishableKey = infoValue("SupabasePublishableKey")

    static var isConfigured: Bool {
        !publishableKey.isEmpty && !publishableKey.hasPrefix("YOUR-")
    }

    private static func infoValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
