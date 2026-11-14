import SwiftUI

/// "Support Wanderer": an optional tip. Nothing in the app depends on it.
struct TipJarView: View {
    @ObservedObject var store: TipJarStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: LiggaSpace.l) {
                header
                statusCard
                tipsSection
                footnote
            }
            .padding(.horizontal, WandererTheme.gutter)
            .padding(.top, LiggaSpace.xs)
            .padding(.bottom, LiggaSpace.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(WandererMotion.animation(WandererMotion.snappy, reduceMotion: reduceMotion), value: store.purchaseState)
            .animation(WandererMotion.animation(WandererMotion.snappy, reduceMotion: reduceMotion), value: store.loadState)
        }
        .background(WandererBackdrop())
        .navigationTitle("Support Wanderer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: store.thanksCount)
        .onChange(of: store.purchaseState) { _, state in
            announce(state)
        }
        .task {
            if store.loadState != .loaded { await store.load() }
        }
        .refreshable { await store.load() }
        .accessibilityIdentifier("tip-jar")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.s) {
            ZStack {
                RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                    .fill(WandererTheme.route)
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(WandererTheme.onAccent)
            }
            .frame(width: WandererTheme.minimumTarget, height: WandererTheme.minimumTarget)
            .accessibilityHidden(true)

            Text("Enjoying Wanderer?")
                .wandererHeading(.title)
                .foregroundStyle(WandererTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Wanderer is free, and every feature stays free. If it helped you plan a trip, you can leave a tip. It's completely optional and doesn't unlock anything.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LiggaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liggaCard()
    }

    // MARK: - Status

    @ViewBuilder
    private var statusCard: some View {
        switch store.purchaseState {
        case .idle, .purchasing:
            EmptyView()
        case .thanks(let tier):
            TipStatusBanner(
                icon: "heart.circle.fill",
                tint: WandererTheme.lagoon,
                title: "Thank you!",
                message: thanksMessage(for: tier),
                actionTitle: "Done",
                action: store.dismissStatus
            )
            .accessibilityIdentifier("tip-jar-thanks")
            .transition(.opacity.combined(with: .move(edge: .top)))
        case .pending:
            TipStatusBanner(
                icon: "hourglass.circle.fill",
                tint: WandererTheme.sea,
                title: "Waiting for approval",
                message: "Your tip will go through once it's approved, for example by a family organiser. You can leave this screen.",
                actionTitle: "OK",
                action: store.dismissStatus
            )
            .accessibilityIdentifier("tip-jar-pending")
            .transition(.opacity.combined(with: .move(edge: .top)))
        case .failed(let message):
            TipStatusBanner(
                icon: "exclamationmark.triangle.fill",
                tint: WandererTheme.coralDeep,
                title: "The tip didn't go through",
                message: message,
                actionTitle: "Dismiss",
                action: store.dismissStatus
            )
            .accessibilityIdentifier("tip-jar-failed")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func thanksMessage(for tier: TipTier) -> String {
        let name = store.products.first(where: { $0.tier == tier })?.title.lowercased() ?? "tip"
        return "Your \(name) means a lot. Thanks for helping keep Wanderer going."
    }

    // MARK: - Tips

    @ViewBuilder
    private var tipsSection: some View {
        switch store.loadState {
        case .idle, .loading where store.products.isEmpty:
            loadingRows
        case .unavailable:
            LiggaRetryCard(
                title: "Tips aren't available right now",
                message: "The App Store didn't return any tips for your region. Wanderer works the same either way.",
                retry: { Task { await store.load() } }
            )
        case .failed(let message):
            LiggaRetryCard(
                title: "Couldn't load tips",
                message: message,
                retry: { Task { await store.load() } }
            )
        default:
            productRows
        }
    }

    private var productRows: some View {
        VStack(spacing: 0) {
            if !store.canMakePayments {
                paymentsDisabledNote
                Divider().overlay(WandererTheme.line)
            }
            ForEach(Array(store.products.enumerated()), id: \.element.id) { index, product in
                if index > 0 {
                    Divider()
                        .overlay(WandererTheme.line)
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? LiggaSpace.m : 72)
                }
                TipRow(
                    product: product,
                    isPurchasing: store.purchaseState == .purchasing(product.tier),
                    isEnabled: store.canMakePayments && !store.isPurchasing
                ) {
                    LiggaHaptics.tap()
                    Task { await store.purchase(product) }
                }
            }
        }
        .liggaCard()
    }

    private var paymentsDisabledNote: some View {
        HStack(alignment: .top, spacing: LiggaSpace.s) {
            Image(systemName: "lock.fill")
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .accessibilityHidden(true)
            Text("In-app purchases are turned off on this device, so tips can't be sent from here.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(LiggaSpace.m)
        .accessibilityElement(children: .combine)
    }

    private var loadingRows: some View {
        VStack(spacing: 0) {
            ForEach(TipTier.allCases) { tier in
                HStack(spacing: LiggaSpace.s) {
                    RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                        .fill(WandererTheme.fillMuted)
                        .frame(width: WandererTheme.minimumTarget, height: WandererTheme.minimumTarget)
                    VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                        SkeletonBlock(width: 120, height: 14)
                        SkeletonBlock(height: 11)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: WandererTheme.controlRadius).fill(WandererTheme.fillMuted).frame(width: 72, height: WandererTheme.minimumTarget)
                }
                .padding(LiggaSpace.m)
            }
        }
        .liggaShimmer()
        .liggaCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading tips")
    }

    private var footnote: some View {
        Text("Tips are one-time payments handled by the App Store. They don't renew, and you can tip again any time.")
            .font(.ligga(.footnote))
            .foregroundStyle(WandererTheme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LiggaSpace.xs)
    }

    private func announce(_ state: TipJarStore.PurchaseState) {
        let message: String
        switch state {
        case .thanks: message = "Tip sent. Thank you!"
        case .pending: message = "Tip waiting for approval"
        case .failed(let detail): message = "The tip didn't go through. \(detail)"
        case .idle, .purchasing: return
        }
        AccessibilityNotification.Announcement(message).post()
    }
}

/// One tip: icon, the App Store's name and description, and its price.
private struct TipRow: View {
    let product: TipProduct
    let isPurchasing: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LiggaSpace.s))
                : AnyLayout(HStackLayout(spacing: LiggaSpace.s))
            layout {
                if !dynamicTypeSize.isAccessibilitySize {
                    icon
                }
                VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                    Text(product.title)
                        .font(.wanderer(.card))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(WandererTheme.ink)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                priceTag
            }
            .padding(.horizontal, LiggaSpace.m)
            .padding(.vertical, LiggaSpace.s)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liggaPressable)
        .disabled(!isEnabled)
        .opacity(isEnabled || isPurchasing ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.title), \(product.displayPrice)")
        .accessibilityValue(isPurchasing ? "Purchasing" : "")
        .accessibilityHint(product.description)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tip-jar-\(product.tier.rawValue)")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                .fill(WandererTheme.routeSoft)
            Image(systemName: product.tier.symbol)
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.accentText)
        }
        .frame(width: WandererTheme.minimumTarget, height: WandererTheme.minimumTarget)
        .accessibilityHidden(true)
    }

    private var priceTag: some View {
        ZStack {
            Text(product.displayPrice)
                .font(.wanderer(.card))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isPurchasing ? 0 : 1)
            if isPurchasing {
                ProgressView().tint(WandererTheme.onPrimary)
            }
        }
        .foregroundStyle(WandererTheme.onPrimary)
        .padding(.horizontal, LiggaSpace.m)
        .padding(.vertical, LiggaSpace.xs)
        .frame(minWidth: WandererTheme.minimumTarget, minHeight: WandererTheme.minimumTarget)
        .background(WandererTheme.primaryFill, in: RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous))
    }
}

/// Inline outcome of the last tip attempt.
private struct TipStatusBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.s) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LiggaSpace.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: LiggaSpace.s))
            layout {
                Image(systemName: icon)
                    .font(.ligga(.title2, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                    Text(title)
                        .wandererHeading(.section)
                        .foregroundStyle(WandererTheme.ink)
                    Text(message)
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            PrimaryButton(title: actionTitle, action: action)
        }
        .padding(LiggaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liggaCard()
    }
}

#Preview("Tip jar") {
    NavigationStack {
        TipJarView(store: .shared)
    }
}
