import AuthenticationServices
import ClerkKit
import Foundation

enum AuthMode {
    case signIn
    case signUp
}

/// Authentication. Clerk is the only identity provider: the same Yoink Labs
/// production instance the website uses. Sign-in is email + a six-digit code.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var isRestoring = true
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    /// Set once a Clerk code has been sent, so the sheet can show the code step.
    @Published private(set) var awaitingCode = false
    @Published private(set) var pendingEmail: String?
    @Published private(set) var pendingMode: AuthMode = .signIn

    private var signedInUserID: String?
    private var signedInEmail: String?

    init() {
        CloudSession.shared.setProvider { [weak self] in
            await self?.validCloudToken()
        }
    }

    var isAuthenticated: Bool { signedInUserID != nil }

    var userID: String? { signedInUserID }

    var userEmail: String { signedInEmail ?? "" }

    // MARK: - Lifecycle

    func restore() async {
        defer { isRestoring = false }
        #if DEBUG
        // Local integration runs can skip Clerk with a Worker test token.
        // Release builds never compile this branch, and the Worker only
        // accepts `test:` tokens when it is itself running in test mode.
        if let token = ProcessInfo.processInfo.environment["WANDERER_TEST_TOKEN"],
           token.hasPrefix("test:") {
            signedInUserID = "local-test-user"
            signedInEmail = ProcessInfo.processInfo.environment["WANDERER_TEST_EMAIL"] ?? "local@example.com"
            CloudSession.shared.token = token
            return
        }
        #endif
        await waitForClerk()
        if let user = Clerk.shared.user, Clerk.shared.session != nil {
            applyClerkUser(user)
            CloudSession.shared.token = try? await Clerk.shared.auth.getToken()
        } else {
            resumePendingVerificationIfTesting()
        }
    }

    /// Debug builds only: if a verification attempt survived a relaunch, show
    /// the code step again so simulator automation can finish it.
    private func resumePendingVerificationIfTesting() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["WANDERER_TEST_CODE"] != nil else { return }
        guard Clerk.shared.client?.signUp != nil || Clerk.shared.client?.signIn != nil else { return }
        awaitingCode = true
        pendingMode = Clerk.shared.client?.signUp != nil ? .signUp : .signIn
        pendingEmail = environment["WANDERER_TEST_EMAIL"]
        #endif
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

    // MARK: - Apple and Google

    /// Native Sign in with Apple through Clerk. Apple returns an ID token and
    /// Clerk signs in or creates the same Yoink Labs account the site uses.
    @discardableResult
    func signInWithApple() async -> Bool {
        await socialSignIn(provider: "Apple") {
            try await Clerk.shared.auth.signInWithApple()
        }
    }

    /// Google through Clerk's OAuth flow in an ASWebAuthenticationSession,
    /// returning to `com.wanderer.ios://callback`.
    @discardableResult
    func signInWithGoogle() async -> Bool {
        await socialSignIn(provider: "Google") {
            try await Clerk.shared.auth.signInWithOAuth(provider: .google)
        }
    }

    private func socialSignIn(provider: String, _ start: () async throws -> TransferFlowResult) async -> Bool {
        guard beginWork() else { return false }
        defer { isWorking = false }
        do {
            let result = try await start()
            let sessionID: String?
            switch result {
            case .signIn(let signIn): sessionID = signIn.createdSessionId
            case .signUp(let signUp): sessionID = signUp.createdSessionId
            }
            if let sessionID {
                try await Clerk.shared.auth.setActive(sessionId: sessionID)
            }
            guard let user = Clerk.shared.user, Clerk.shared.session != nil else {
                errorMessage = Self.incompleteSocialMessage(provider: provider)
                return false
            }
            applyClerkUser(user)
            CloudSession.shared.token = try? await Clerk.shared.auth.getToken()
            awaitingCode = false
            return true
        } catch {
            if Self.isCancellation(error) {
                errorMessage = nil
            } else {
                errorMessage = friendly(error)
            }
            return false
        }
    }

    nonisolated static func incompleteSocialMessage(provider: String) -> String {
        "\(provider) didn't finish signing you in. Try again, or continue with email."
    }

    /// Closing the Apple sheet or the Google browser is not an error.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if let auth = error as? ASAuthorizationError, auth.code == .canceled { return true }
        if let web = error as? ASWebAuthenticationSessionError, web.code == .canceledLogin { return true }
        let ns = error as NSError
        return (ns.domain == ASAuthorizationError.errorDomain && ns.code == ASAuthorizationError.canceled.rawValue)
            || (ns.domain == ASWebAuthenticationSessionError.errorDomain && ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue)
    }

    // MARK: - Sign out

    func signOut() async {
        try? await Clerk.shared.auth.signOut()
        signedInUserID = nil
        signedInEmail = nil
        CloudSession.shared.token = nil
        OfflineReadCache.shared.scope = nil
        OfflineReadCache.shared.clear()
        awaitingCode = false
    }

    // MARK: - Tokens

    /// Returns a Clerk session JWT, refreshing it when the SDK's cache is
    /// stale. The API client calls this through `CloudSession`.
    func validCloudToken() async -> String? {
        guard signedInUserID != nil else { return nil }
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
        OfflineReadCache.shared.scope = user.id
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
        return error.localizedDescription
    }
}
