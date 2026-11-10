import ClerkKit
import Foundation
import Supabase

enum WandererSupabase {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )
}

enum AuthMode {
    case signIn
    case signUp
}

/// Authentication for both backends.
///
/// - **Clerk** (default): the same Yoink Labs production instance as
///   yoinklabs.dev. Sign-in is email + verification code; the Clerk iOS SDK
///   owns the session, refresh and secure storage.
/// - **Supabase** (legacy): the previous email/password session, kept only
///   while the cloud backend is unavailable so the app still builds and runs.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Supabase.Session?
    @Published private(set) var isRestoring = true
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    /// Set once a Clerk code has been sent, so the sheet can show the code step.
    @Published private(set) var awaitingCode = false
    @Published private(set) var pendingEmail: String?
    @Published private(set) var pendingMode: AuthMode = .signIn

    private var signedInUserID: String?
    private var signedInEmail: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
        CloudSession.shared.setProvider { [weak self] in
            await self?.validCloudToken()
        }
    }

    var usesClerk: Bool { BackendMode.isCloudAvailable }

    var isAuthenticated: Bool {
        if usesClerk { return signedInUserID != nil }
        return session != nil
    }

    var userID: String? {
        if usesClerk { return signedInUserID }
        return session?.user.id.uuidString
    }

    var userEmail: String {
        if usesClerk { return signedInEmail ?? "" }
        return session?.user.email ?? ""
    }

    // MARK: - Lifecycle

    func restore() async {
        defer { isRestoring = false }

        if usesClerk {
            await waitForClerk()
            if let user = Clerk.shared.user, Clerk.shared.session != nil {
                applyClerkUser(user)
                CloudSession.shared.token = try? await Clerk.shared.auth.getToken()
            }
            return
        }

        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    private func waitForClerk() async {
        for _ in 0..<40 {
            if Clerk.shared.isLoaded { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Email code sign-in

    /// Sends a sign-in code. Returns false when Clerk has no account for that
    /// email so the sheet can offer "create account" instead.
    @discardableResult
    func sendSignInCode(email: String) async -> Bool {
        guard beginWork() else { return false }
        defer { isWorking = false }

        if !usesClerk {
            errorMessage = "Cloud sign-in is not configured for this build."
            return false
        }

        do {
            _ = try await Clerk.shared.auth.signInWithEmailCode(emailAddress: email)
            pendingEmail = email
            pendingMode = .signIn
            awaitingCode = true
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    /// Creates the account and sends the verification code. Clerk requires a
    /// password on this instance even though sign-in uses email codes.
    @discardableResult
    func createAccount(email: String, password: String) async -> Bool {
        guard beginWork() else { return false }
        defer { isWorking = false }

        if !usesClerk {
            errorMessage = "Cloud sign-in is not configured for this build."
            return false
        }

        do {
            let signUp = try await Clerk.shared.auth.signUp(emailAddress: email, password: password)
            _ = try await signUp.sendEmailCode()
            pendingEmail = email
            pendingMode = .signUp
            awaitingCode = true
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    @discardableResult
    func verifyCode(_ code: String) async -> Bool {
        guard beginWork() else { return false }
        defer { isWorking = false }

        guard usesClerk else { return false }

        do {
            let sessionID: String?
            if let signUp = Clerk.shared.client?.signUp {
                let verified = try await signUp.verifyEmailCode(code)
                sessionID = verified.createdSessionId
            } else if let signIn = Clerk.shared.client?.signIn {
                let verified = try await signIn.verifyCode(code)
                sessionID = verified.createdSessionId
            } else {
                errorMessage = "That code has expired. Start again."
                return false
            }

            guard let sessionID else {
                errorMessage = "That code didn't finish the sign-in. Request a new one."
                return false
            }
            try await Clerk.shared.auth.setActive(sessionId: sessionID)
            if let user = Clerk.shared.user {
                applyClerkUser(user)
            }
            CloudSession.shared.token = try? await Clerk.shared.auth.getToken()
            awaitingCode = false
            pendingEmail = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    @discardableResult
    func resendCode() async -> Bool {
        guard let pendingEmail else { return false }
        if pendingMode == .signUp, let signUp = Clerk.shared.client?.signUp {
            guard beginWork() else { return false }
            defer { isWorking = false }
            do {
                _ = try await signUp.sendEmailCode()
                return true
            } catch {
                errorMessage = friendly(error)
                return false
            }
        }
        return await sendSignInCode(email: pendingEmail)
    }

    func cancelCode() {
        awaitingCode = false
        pendingEmail = nil
        errorMessage = nil
    }

    // MARK: - Sign out

    func signOut() async {
        if usesClerk {
            try? await Clerk.shared.auth.signOut()
            signedInUserID = nil
            signedInEmail = nil
            CloudSession.shared.token = nil
        }
        do {
            try await client.auth.signOut()
        } catch {
            // A failed network sign-out should still clear the local session.
        }
        session = nil
        awaitingCode = false
    }

    // MARK: - Tokens

    /// Returns a Clerk session JWT, refreshing it when the SDK's cache is
    /// stale. The API client calls this through `CloudSession`.
    func validCloudToken() async -> String? {
        guard usesClerk, signedInUserID != nil else { return nil }
        return try? await Clerk.shared.auth.getToken()
    }

    // MARK: - Helpers

    private func beginWork() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        return true
    }

    private func applyClerkUser(_ user: ClerkKit.User) {
        signedInUserID = user.id
        signedInEmail = user.primaryEmailAddress?.emailAddress
    }

    private func friendly(_ error: Error) -> String {
        if let apiError = error as? ClerkAPIError {
            switch apiError.code {
            case "form_identifier_not_found":
                return "No account uses that email yet."
            case "form_code_incorrect":
                return "That code doesn't match. Check it and try again."
            case "verification_expired":
                return "That code expired. Send a new one."
            case "form_password_length_too_short":
                return "Use a password with at least 15 characters."
            case "form_password_pwned":
                return "That password has appeared in a breach. Choose another."
            case "form_identifier_exists":
                return "That email already has an account. Sign in instead."
            case "form_param_format_invalid":
                return "Enter a valid email address."
            default:
                return apiError.longMessage ?? apiError.message ?? "Sign-in failed. Try again."
            }
        }
        if let clientError = error as? ClerkClientError {
            return clientError.localizedDescription
        }
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("invalid login credentials") {
            return "That email and password don't match. Try again or sign up."
        }
        return message
    }
}
