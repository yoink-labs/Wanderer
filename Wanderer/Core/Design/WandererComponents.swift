import SwiftUI

struct WandererMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(WandererTheme.route)
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(WandererTheme.onAccent)
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
                        .font(.wanderer(.card))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(WandererTheme.onPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiggaSpace.s)
            .frame(minHeight: WandererTheme.buttonHeight)
            .padding(.horizontal, LiggaSpace.m)
            .foregroundStyle(isEnabled ? WandererTheme.onPrimary : WandererTheme.muted)
            .background(
                RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                    .fill(isEnabled ? WandererTheme.primaryFill : WandererTheme.fillMuted)
            )
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous))
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
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiggaSpace.s)
            .frame(minHeight: WandererTheme.buttonHeight)
            .padding(.horizontal, LiggaSpace.m)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                            .stroke(WandererTheme.line, lineWidth: background == .white ? 1 : 0)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous))
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LiggaSpace.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LiggaSpace.s))
        layout {
            VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                Text(title)
                    .wandererHeading(.section)
                    .foregroundStyle(WandererTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: LiggaSpace.xs) }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.accentText)
                        .frame(minWidth: WandererTheme.minimumTarget, minHeight: WandererTheme.minimumTarget)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

struct AvatarStack: View {
    let initials: [String]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: -size * 0.22) {
            ForEach(initials.indices, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill([WandererTheme.dust, WandererTheme.desert.opacity(0.55), WandererTheme.salmon.opacity(0.35)][index % 3])
                    Text(initials[index])
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(WandererTheme.ink)
                }
                .frame(width: size, height: size)
                .overlay(Circle().stroke(WandererTheme.card, lineWidth: 2))
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
            .foregroundStyle(tone == .strong ? WandererTheme.onPrimary : WandererTheme.ink)
            .padding(.horizontal, LiggaSpace.xs)
            .padding(.vertical, 3)
            .background(
                tone == .strong ? WandererTheme.primaryFill : WandererTheme.fillMuted,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.s) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LiggaSpace.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: LiggaSpace.s))
            layout {
                Image(systemName: "wifi.exclamationmark")
                    .font(.ligga(.title3, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                    Text(title)
                        .wandererHeading(.section)
                        .foregroundStyle(WandererTheme.ink)
                    if let message {
                        Text(message)
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(title: "Retry", isLoading: isRetrying, action: retry)
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
                .foregroundStyle(WandererTheme.muted)
                .accessibilityHidden(true)
            Text(title)
                .wandererHeading(.section)
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
                        .foregroundStyle(WandererTheme.onPrimary)
                        .padding(.horizontal, LiggaSpace.m)
                        .frame(minHeight: 44)
                        .background(WandererTheme.primaryFill, in: Capsule())
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
