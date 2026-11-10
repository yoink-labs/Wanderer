import Foundation

/// Build-time configuration for the Cloudflare Worker backend and Clerk.
///
/// Values come from `Config/Cloud.local.xcconfig` (gitignored) through
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

/// Which storage the app talks to. Supabase stays the default until the Worker
/// is deployed and Clerk sign-in is verified end to end; the switch lives in
/// one place so a cutover is a config change, not a code change.
enum BackendMode: String {
    case supabase
    case cloud

    static let defaultsKey = "wanderer.backendMode"

    static var current: BackendMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let mode = BackendMode(rawValue: raw) {
                return mode
            }
            // The cloud backend is the default after the cutover; builds
            // without a Worker URL fall back to Supabase automatically.
            return .cloud
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// Cloud mode needs both the API URL and a signed-in cloud session.
    static var isCloudAvailable: Bool {
        CloudConfiguration.isAPIConfigured && CloudConfiguration.isClerkConfigured
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
