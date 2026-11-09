import Foundation
import Supabase

enum WandererSupabase {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isRestoring = true
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

    var isAuthenticated: Bool { session != nil }
    var userEmail: String { session?.user.email ?? "" }

    func restore() async {
        defer { isRestoring = false }
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    func signIn(email: String, password: String) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

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
        do {
            try await client.auth.signOut()
        } catch {
            // A failed network sign-out should still clear the local session.
        }
        session = nil
    }

    private func friendly(_ error: Error) -> String {
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
