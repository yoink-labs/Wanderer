import Foundation

/// Build-time configuration for the Cloudflare Worker backend and Clerk.
///
/// Values come from `Config/App.local.xcconfig` (gitignored) through
/// Info.plist. Nothing here is a secret: the Clerk publishable key and the
/// Worker URL are both safe to ship, and the Worker enforces access.
enum CloudConfiguration {
    static let apiURL: URL? = {
        guard let raw = infoValue("WandererAPIURL"), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }()

    static let clerkFrontendAPI: String? = {
        guard let raw = infoValue("ClerkFrontendAPI"), !raw.isEmpty else { return nil }
        return raw
    }()

    static let clerkPublishableKey: String? = {
        guard let raw = infoValue("ClerkPublishableKey"), !raw.isEmpty else { return nil }
        return raw
    }()

    static let callbackScheme = "wanderer"

    static var isAPIConfigured: Bool { apiURL != nil }
    static var isClerkConfigured: Bool { clerkFrontendAPI != nil && clerkPublishableKey != nil }

    private static func infoValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// Supplies the Clerk session JWT to the API client. Kept as a closure so the
/// client stays testable and has no dependency on the auth store.
struct APIAuth: Sendable {
    let token: @Sendable () async -> String?

    static let none = APIAuth { nil }

    static func bearer(_ provider: @escaping @Sendable () async -> String?) -> APIAuth {
        APIAuth(token: provider)
    }
}

/// One-time cleanup for devices upgraded from the Supabase build. Those
/// installs may still hold a backend switch and a "has Supabase account" flag;
/// neither means anything now. Removing them is idempotent, and the stale
/// Supabase Keychain session is simply never read again, so such a device
/// lands on the Clerk email sign-in like any signed-out install.
enum LegacyBackendCleanup {
    static let legacyKeys = ["wanderer.backendMode", "wanderer.hasSupabaseAccount"]
    static let doneKey = "wanderer.legacyBackendCleanupDone"

    @discardableResult
    static func run(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: doneKey) else { return false }
        var removed = false
        for key in legacyKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            removed = true
        }
        defaults.set(true, forKey: doneKey)
        return removed
    }
}
