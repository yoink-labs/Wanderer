import SwiftUI

struct EmailAuthSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wanderer.isGuest") private var isGuest = false

    @State private var mode: Mode
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError: String?
    @State private var showPassword = false

    @FocusState private var focus: Field?

    init(startInSignUp: Bool = false) {
        _mode = State(initialValue: startInSignUp ? .signUp : .signIn)
    }

    enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Sign up"
    }

    private enum Field: Hashable {
        case email, password, confirm
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private var canSubmit: Bool {
        guard emailLooksValid, password.count >= 6 else { return false }
        if mode == .signUp && password != confirmPassword { return false }
        return true
    }

    /// Short hint under the fields explaining why the button is disabled.
    private var requirementHint: String? {
        guard !auth.isWorking else { return nil }
        if !trimmedEmail.isEmpty && !emailLooksValid && focus != .email {
            return "Enter an email like name@example.com."
        }
        if !password.isEmpty && password.count < 6 {
            return "Passwords need at least 6 characters."
        }
        if mode == .signUp && !confirmPassword.isEmpty && password != confirmPassword {
            return "Passwords don't match yet."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiggaSpace.l) {
                    VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                        Text(mode == .signIn ? "Welcome back" : "Create your account")
                            .font(.ligga(.title, weight: .bold))
                            .foregroundStyle(WandererTheme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(mode == .signIn
                             ? "Sign in to sync your trips across devices."
                             : "One account keeps every itinerary, booking and receipt together.")
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                    }

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(auth.isWorking)
                    .onChange(of: mode) { _, newMode in
                        localError = nil
                        auth.errorMessage = nil
                        if newMode == .signIn {
                            confirmPassword = ""
                            if focus == .confirm { focus = .password }
                        }
                    }

                    VStack(spacing: LiggaSpace.s) {
                        fieldShell(icon: "envelope", field: .email) {
                            TextField("Email", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focus, equals: .email)
                                .onSubmit { focus = .password }
                                .accessibilityIdentifier("auth-email-field")
                        }

                        fieldShell(icon: "lock", field: .password, trailing: revealButton) {
                            passwordInput("Password", text: $password)
                                // Sign-in uses `.password` for AutoFill. Sign-up uses
                                // `.oneTimeCode` so iOS doesn't cover the field with the
                                // "Use Strong Password?" sheet.
                                .textContentType(mode == .signIn ? .password : .oneTimeCode)
                                .submitLabel(mode == .signIn ? .go : .next)
                                .focused($focus, equals: .password)
                                .onSubmit {
                                    if mode == .signUp {
                                        focus = .confirm
                                    } else {
                                        submit()
                                    }
                                }
                                .accessibilityIdentifier("auth-password-field")
                        }

                        if mode == .signUp {
                            fieldShell(icon: "lock.rotation", field: .confirm) {
                                passwordInput("Confirm password", text: $confirmPassword)
                                    .textContentType(.oneTimeCode)
                                    .submitLabel(.go)
                                    .focused($focus, equals: .confirm)
                                    .onSubmit { submit() }
                                    .accessibilityIdentifier("auth-confirm-field")
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .disabled(auth.isWorking)

                    if let message = localError ?? auth.errorMessage {
                        HStack(alignment: .top, spacing: LiggaSpace.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .accessibilityHidden(true)
                            Text(message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.accentText)
                        .padding(LiggaSpace.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WandererTheme.coralSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityElement(children: .combine)
                    } else if let requirementHint {
                        Text(requirementHint)
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                            .transition(.opacity)
                    }

                    PrimaryButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        icon: nil,
                        isEnabled: canSubmit,
                        isLoading: auth.isWorking
                    ) {
                        submit()
                    }
                    .accessibilityIdentifier("auth-submit")

                    if mode == .signIn {
                        Button("Forgot your password?") {
                            localError = "Password reset is coming next. For now, create a new account or ask an admin to reset it."
                        }
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.accentText)
                        .frame(minHeight: 44)
                        .disabled(auth.isWorking)
                    }
                }
                .padding(WandererTheme.gutter)
                .animation(.easeOut(duration: 0.2), value: mode)
                .animation(.easeOut(duration: 0.2), value: requirementHint)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(auth.isWorking)
                }
            }
            .interactiveDismissDisabled(auth.isWorking)
            .onAppear {
                if focus == nil { focus = .email }
            }
        }
    }

    // MARK: - Fields

    private var revealButton: some View {
        Button {
            // Swapping SecureField and TextField drops focus; put it back.
            let current = focus
            showPassword.toggle()
            DispatchQueue.main.async { focus = current }
        } label: {
            Image(systemName: showPassword ? "eye.slash" : "eye")
                .font(.ligga(.body))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
    }

    @ViewBuilder
    private func passwordInput(_ placeholder: String, text: Binding<String>) -> some View {
        if showPassword {
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            SecureField(placeholder, text: text)
        }
    }

    private func fieldShell<Content: View>(
        icon: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        fieldShell(icon: icon, field: field, trailing: EmptyView(), content: content)
    }

    /// White input well. The focused field gets a 2pt peach ring, the only
    /// stroke on this screen.
    private func fieldShell<Trailing: View, Content: View>(
        icon: String,
        field: Field,
        trailing: Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focus == field
        return HStack(spacing: LiggaSpace.s) {
            Image(systemName: icon)
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(isFocused ? WandererTheme.ink : WandererTheme.muted)
                .frame(width: 24)
                .accessibilityHidden(true)
            content()
                .font(.ligga(.body))
                .foregroundStyle(WandererTheme.ink)
            trailing
        }
        .padding(.leading, LiggaSpace.m)
        .padding(.trailing, LiggaSpace.xxs)
        .frame(minHeight: 52)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? WandererTheme.peach : WandererTheme.line.opacity(0.8), lineWidth: isFocused ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    // MARK: - Submit

    private func submit() {
        guard !auth.isWorking else { return }
        localError = nil

        guard emailLooksValid else {
            localError = "Enter a valid email address."
            focus = .email
            return
        }
        guard password.count >= 6 else {
            localError = "Use a password with at least 6 characters."
            focus = .password
            return
        }
        guard mode == .signIn || password == confirmPassword else {
            localError = "Passwords don't match."
            focus = .confirm
            return
        }

        focus = nil
        let email = trimmedEmail
        Task {
            if mode == .signIn {
                await auth.signIn(email: email, password: password)
            } else {
                await auth.signUp(email: email, password: password)
            }

            if auth.isAuthenticated {
                LiggaHaptics.success()
                isGuest = false
                dismiss()
            } else if auth.errorMessage?.hasPrefix("Check your email") != true {
                LiggaHaptics.warning()
            }
        }
    }
}

#Preview {
    EmailAuthSheet()
        .environmentObject(AuthStore())
}
