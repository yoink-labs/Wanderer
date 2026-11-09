import SwiftUI

/// Top-level flow: language onboarding → auth → the app.
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("wanderer.selectedLanguage") private var selectedLanguage = ""
    @AppStorage("wanderer.isGuest") private var isGuest = false

    private var phase: Phase {
        if selectedLanguage.isEmpty { return .language }
        if auth.isRestoring { return .restoring }
        if auth.session == nil && !isGuest { return .auth }
        return .app
    }

    var body: some View {
        Group {
            switch phase {
            case .language:
                LanguagePickerView()
                    .transition(.opacity)
            case .restoring:
                LaunchView()
                    .transition(.opacity)
            case .auth:
                SignInView()
                    .transition(.opacity)
            case .app:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
        .task {
            await auth.restore()
        }
    }

    private enum Phase: Equatable {
        case language, restoring, auth, app
    }
}

private struct LaunchView: View {
    @State private var showSpinner = false

    var body: some View {
        ZStack {
            WandererTheme.charcoal.ignoresSafeArea()
            VStack(spacing: LiggaSpace.m) {
                WandererMark(size: 56)
                // Only show a spinner when restoring is actually slow, so a
                // fast launch doesn't flash one.
                ProgressView()
                    .tint(.white)
                    .opacity(showSpinner ? 1 : 0)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeIn(duration: 0.2)) { showSpinner = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Wanderer")
    }
}

#Preview {
    RootView()
        .environmentObject(AuthStore())
}
