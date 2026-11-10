import SwiftUI

/// Email-only authentication with Clerk's verification code.
///
/// Sign-in always uses a six-digit code sent to the email address. Creating an
/// account also needs a password because the Yoink Labs Clerk instance requires
/// one at sign-up, even though it is never used to sign in.
struct EmailAuthSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wanderer.isGuest") private var isGuest = false

    @State private var mode: Mode
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var code = ""
    @State private var localError: String?
    @State private var showPassword = false

    @FocusState private var focus: Field?

    init(startInSignUp: Bool = false) {
        _mode = State(initialValue: startInSignUp ? .signUp : .signIn)
    }

    enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    private enum Field: Hashable {
        case email, password, confirm, code
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private var passwordIsLongEnough: Bool { password.count >= 15 }

    private var canSendCode: Bool {
        guard emailLooksValid else { return false }
        if mode == .signUp {
            return passwordIsLongEnough && password == confirmPassword
        }
        return true
    }

    private var canVerify: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
    }

    private var requirementHint: String? {
        guard !auth.isWorking else { return nil }
        if !trimmedEmail.isEmpty && !emailLooksValid && focus != .email {
            return "Enter an email like name@example.com."
        }
        if mode == .signUp, !password.isEmpty, !passwordIsLongEnough {
            return "This Clerk instance requires at least 15 characters."
        }
        if mode == .signUp, !confirmPassword.isEmpty, password != confirmPassword {
            return "Passwords don't match yet."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiggaSpace.l) {
                    if auth.awaitingCode {
                        codeStep
                    } else {
                        emailStep
                    }
                }
                .padding(WandererTheme.gutter)
                .animation(.easeOut(duration: 0.2), value: auth.awaitingCode)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle(auth.awaitingCode ? "Verify email" : "Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(auth.isWorking)
                }
            }
            .interactiveDismissDisabled(auth.isWorking)
            .onAppear {
                applyTestPrefill()
                if !auth.awaitingCode, focus == nil { focus = .email }
            }
            .onChange(of: auth.awaitingCode) { _, awaiting in
                if awaiting { applyTestPrefill() }
            }
        }
    }

    // MARK: - Steps

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.l) {
            VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                Text(mode == .signIn ? "Welcome back" : "Create your account")
                    .font(.ligga(.title, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(mode == .signIn
                     ? "We'll email you a six-digit code. No password to remember."
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
                        .onSubmit {
                            focus = mode == .signUp ? .password : nil
                        }
                        .accessibilityIdentifier("auth-email-field")
                }

                if mode == .signUp {
                    fieldShell(icon: "lock", field: .password, trailing: revealButton) {
                        passwordInput("Password (15+ characters)", text: $password)
                            .textContentType(.oneTimeCode)
                            .submitLabel(.next)
                            .focused($focus, equals: .password)
                            .onSubmit { focus = .confirm }
                            .accessibilityIdentifier("auth-password-field")
                    }

                    fieldShell(icon: "lock.rotation", field: .confirm) {
                        passwordInput("Confirm password", text: $confirmPassword)
                            .textContentType(.oneTimeCode)
                            .submitLabel(.go)
                            .focused($focus, equals: .confirm)
                            .onSubmit { sendCode() }
                            .accessibilityIdentifier("auth-confirm-field")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .disabled(auth.isWorking)

            messageArea

            PrimaryButton(
                title: mode == .signIn ? "Email me a code" : "Create account",
                icon: "paperplane.fill",
                isEnabled: canSendCode,
                isLoading: auth.isWorking
            ) {
                sendCode()
            }
            .accessibilityIdentifier("auth-submit")

            if mode == .signIn, auth.errorMessage?.contains("No account") == true {
                Button("Create an account instead") {
                    mode = .signUp
                    localError = nil
                    auth.errorMessage = nil
                }
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.accentText)
                .frame(minHeight: 44)
            }

            Text("By continuing you agree to the Terms and Privacy Policy.")
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.l) {
            VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                Text("Check your email")
                    .font(.ligga(.title, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("We sent a six-digit code to \(auth.pendingEmail ?? trimmedEmail).")
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
            }

            fieldShell(icon: "number", field: .code) {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focus, equals: .code)
                    .accessibilityIdentifier("auth-code-field")
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                    }
            }
            .disabled(auth.isWorking)

            messageArea

            PrimaryButton(
                title: "Verify",
                icon: "checkmark",
                isEnabled: canVerify,
                isLoading: auth.isWorking
            ) {
                verify()
            }
            .accessibilityIdentifier("auth-verify")

            HStack(spacing: LiggaSpace.m) {
                Button("Resend code") {
                    Task {
                        let sent = await auth.resendCode()
                        if sent { LiggaHaptics.success() }
                    }
                }
                .disabled(auth.isWorking)

                Button("Use a different email") {
                    code = ""
                    auth.cancelCode()
                    focus = .email
                }
                .disabled(auth.isWorking)
            }
            .font(.ligga(.subheadline, weight: .semibold))
            .foregroundStyle(WandererTheme.accentText)
        }
    }

    @ViewBuilder
    private var messageArea: some View {
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
    }

    /// Debug builds can prefill the email and code from the launch
    /// environment so simulator automation does not depend on the software
    /// keyboard. Release builds compile this out.
    private func applyTestPrefill() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if email.isEmpty, let value = environment["WANDERER_TEST_EMAIL"] {
            email = value
        }
        if password.isEmpty, let value = environment["WANDERER_TEST_PASSWORD"] {
            password = value
            confirmPassword = value
        }
        if code.isEmpty, auth.awaitingCode, let value = environment["WANDERER_TEST_CODE"] {
            code = value
        }
        #endif
    }

    // MARK: - Fields

    private var revealButton: some View {
        Button {
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
                .stroke(isFocused ? WandererTheme.coral : WandererTheme.line.opacity(0.8), lineWidth: isFocused ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    // MARK: - Actions

    private func sendCode() {
        guard !auth.isWorking else { return }
        localError = nil

        guard emailLooksValid else {
            localError = "Enter a valid email address."
            focus = .email
            return
        }
        if mode == .signUp {
            guard passwordIsLongEnough else {
                localError = "Use a password with at least 15 characters."
                focus = .password
                return
            }
            guard password == confirmPassword else {
                localError = "Passwords don't match."
                focus = .confirm
                return
            }
        }

        focus = nil
        let address = trimmedEmail
        Task {
            let sent = mode == .signIn
                ? await auth.sendSignInCode(email: address)
                : await auth.createAccount(email: address, password: password)
            if sent {
                LiggaHaptics.success()
                focus = .code
            } else {
                LiggaHaptics.warning()
            }
        }
    }

    private func verify() {
        guard !auth.isWorking else { return }
        localError = nil
        focus = nil
        let entered = code.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await auth.verifyCode(entered)
            if ok {
                LiggaHaptics.success()
                isGuest = false
                dismiss()
            } else {
                LiggaHaptics.warning()
                focus = .code
            }
        }
    }
}

#Preview {
    EmailAuthSheet()
        .environmentObject(AuthStore())
}
