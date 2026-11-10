import Foundation
import Supabase

enum WandererSupabase {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )
}

/// Authentication for both backends.
///
/// - **Supabase** (current default): the existing email/password session.
/// - **Clerk** (cloud mode): the same Yoink Labs production instance the
///   website uses. The session JWT is what the Worker verifies; the app keeps
///   the Clerk client token in the Keychain so sign-in survives relaunch.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var clerkSession: ClerkSession?
    @Published private(set) var isRestoring = true
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let clerkStore = ClerkSessionStore()
    private var clerkClient: ClerkAuthClient? {
        guard let domain = CloudConfiguration.clerkFrontendAPI,
              let url = URL(string: domain) else { return nil }
        return ClerkAuthClient(frontendAPI: url)
    }

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
        CloudSession.shared.setProvider { [weak self] in
            await self?.validCloudToken()
        }
    }

    var isAuthenticated: Bool {
        if session != nil || clerkSession != nil { return true }
        #if DEBUG
        if CloudSession.shared.debugToken != nil { return true }
        #endif
        return false
    }

    var userEmail: String {
        session?.user.email ?? clerkSession?.email ?? ""
    }

    var usesClerk: Bool {
        BackendMode.current == .cloud && BackendMode.isCloudAvailable
    }

    // MARK: - Lifecycle

    func restore() async {
        defer { isRestoring = false }

        if usesClerk {
            guard let stored = clerkStore.load() else { return }
            clerkSession = stored
            CloudSession.shared.token = stored.jwt
            if let expiresAt = stored.expiresAt, expiresAt.timeIntervalSinceNow < 60 {
                await refreshClerkSession()
            }
            return
        }

        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    // MARK: - Sign in / up / out

    func signIn(email: String, password: String) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if usesClerk {
            guard let clerkClient else {
                errorMessage = "Sign-in is not configured for this build."
                return
            }
            do {
                let created = try await clerkClient.signIn(email: email, password: password)
                try persist(created)
            } catch {
                errorMessage = friendly(error)
            }
            return
        }

        do {
            session = try await client.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = friendly(error)
        }
    }

    func signUp(email: String, password: String) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if usesClerk {
            guard let clerkClient else {
                errorMessage = "Sign-in is not configured for this build."
                return
            }
            do {
                let created = try await clerkClient.signUp(email: email, password: password)
                try persist(created)
            } catch {
                errorMessage = friendly(error)
            }
            return
        }

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            session = response.session
            if response.session == nil {
                errorMessage = "Check your email to confirm your account, then sign in."
            }
        } catch {
            errorMessage = friendly(error)
        }
    }

    func signOut() async {
        if usesClerk || clerkSession != nil {
            clerkStore.clear()
            clerkSession = nil
            CloudSession.shared.token = nil
        }
        do {
            try await client.auth.signOut()
        } catch {
            // A failed network sign-out should still clear the local session.
        }
        session = nil
    }

    // MARK: - Tokens

    /// Returns a JWT that is valid for at least the next minute, refreshing it
    /// when needed. The API client calls this through `CloudSession`.
    func validCloudToken() async -> String? {
        guard let current = clerkSession else { return nil }
        if let expiresAt = current.expiresAt, expiresAt.timeIntervalSinceNow < 60 {
            await refreshClerkSession()
        }
        return clerkSession?.jwt
    }

    private func refreshClerkSession() async {
        guard let clerkClient, let current = clerkSession else { return }
        do {
            let refreshed = try await clerkClient.refresh(current)
            try persist(refreshed)
        } catch {
            // Keep the old token; the next API call will surface the 401 and the
            // UI can ask for a fresh sign-in.
            errorMessage = "Your session expired. Sign in again to continue."
        }
    }

    private func persist(_ created: ClerkSession) throws {
        try clerkStore.save(created)
        clerkSession = created
        CloudSession.shared.token = created.jwt
        errorMessage = nil
    }

    private func friendly(_ error: Error) -> String {
        if let clerkError = error as? ClerkAuthError {
            return clerkError.errorDescription ?? "Sign-in failed. Try again."
        }
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("invalid login credentials") {
            return "That email and password don't match. Try again or sign up."
        }
        if message.localizedCaseInsensitiveContains("already registered") {
            return "That email already has an account. Try signing in."
        }
        if message.localizedCaseInsensitiveContains("password should be") {
            return "Use a password with at least 6 characters."
        }
        return message
    }
}
