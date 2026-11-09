import SwiftUI

struct WandererMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(WandererTheme.peach)
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Charcoal, full-width primary action. Plays a light tap haptic.
struct PrimaryButton: View {
    let title: String
    var icon: String?
    var isEnabled: Bool = true
    /// Shows a spinner in place of the label and blocks taps.
    var isLoading: Bool = false
    let action: () -> Void

    private var isActive: Bool { isEnabled && !isLoading }

    var body: some View {
        Button {
            LiggaHaptics.tap()
            action()
        } label: {
            ZStack {
                HStack(spacing: LiggaSpace.xs) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.ligga(.body, weight: .semibold))
                    }
                    Text(title)
                        .font(.ligga(.headline, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, LiggaSpace.m)
            .foregroundStyle(isEnabled ? .white : WandererTheme.muted)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? WandererTheme.charcoal : WandererTheme.fillMuted)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.liggaPressable)
        .disabled(!isActive)
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
    }
}

struct SocialSignInButton: View {
    let title: String
    let icon: String
    var foreground: Color = WandererTheme.ink
    var background: Color = .white
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            LiggaHaptics.tap()
            action()
        } label: {
            ZStack {
                HStack(spacing: LiggaSpace.s) {
                    Image(systemName: icon)
                        .font(.ligga(.body, weight: .semibold))
                    Text(title)
                        .font(.ligga(.body, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, LiggaSpace.m)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WandererTheme.line, lineWidth: background == .white ? 1 : 0)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.liggaPressable)
        .disabled(!isEnabled || isLoading)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                Text(title)
                    .font(.ligga(.title3, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.accentText)
                    .frame(minHeight: 44)
            }
        }
    }
}

struct AvatarStack: View {
    let initials: [String]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(initials.indices, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill([WandererTheme.dust, WandererTheme.desert.opacity(0.55), WandererTheme.salmon.opacity(0.35)][index % 3])
                    Text(initials[index])
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(WandererTheme.ink)
                }
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }
}

/// Compact status capsule ("In progress", "Past"). Never wraps.
struct LiggaStatusChip: View {
    enum Tone {
        case strong, quiet
    }

    let title: String
    var tone: Tone = .strong

    var body: some View {
        Text(title)
            .font(.ligga(.caption, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tone == .strong ? Color.white : WandererTheme.ink)
            .padding(.horizontal, LiggaSpace.xs)
            .padding(.vertical, 3)
            .background(
                tone == .strong ? WandererTheme.charcoal : WandererTheme.fillMuted,
                in: Capsule()
            )
    }
}

/// Inline failure with a retry action. Use instead of an alert when a screen's
/// own data didn't load.
struct LiggaRetryCard: View {
    let title: String
    var message: String?
    var isRetrying: Bool = false
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LiggaSpace.s) {
            Image(systemName: "wifi.exclamationmark")
                .font(.ligga(.title3, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                if let message {
                    Text(message)
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                LiggaHaptics.tap()
                retry()
            } label: {
                ZStack {
                    Text("Retry").opacity(isRetrying ? 0 : 1)
                    if isRetrying {
                        ProgressView().tint(.white)
                    }
                }
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, LiggaSpace.m)
                .frame(minHeight: 36)
                .background(WandererTheme.charcoal, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.liggaPressable)
            .disabled(isRetrying)
            .accessibilityIdentifier("retry-button")
        }
        .padding(LiggaSpace.m)
        .liggaCard()
        .accessibilityElement(children: .contain)
    }
}

/// Centered empty state with an optional action.
struct LiggaEmptyState: View {
    let icon: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: LiggaSpace.s) {
            Image(systemName: icon)
                .font(.ligga(.largeTitle, weight: .semibold))
                .foregroundStyle(WandererTheme.muted.opacity(0.7))
                .accessibilityHidden(true)
            Text(title)
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button {
                    LiggaHaptics.tap()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, LiggaSpace.m)
                        .frame(minHeight: 44)
                        .background(WandererTheme.charcoal, in: Capsule())
                }
                .buttonStyle(.liggaPressable)
                .padding(.top, LiggaSpace.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LiggaSpace.xl)
        .padding(.horizontal, LiggaSpace.m)
    }
}
