import SwiftUI

/// A soft highlight that sweeps across redacted placeholder content.
/// Static under Reduce Motion.
struct LiggaShimmer: ViewModifier {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    phase = -1
                    withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

/// Rounded placeholder block used to sketch a layout while data loads.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(WandererTheme.fillMuted)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

extension View {
    /// Redacts the real layout and adds a shimmer while `isLoading` is true.
    /// Hides it from VoiceOver and disables hit testing so placeholders can't
    /// be tapped.
    func liggaSkeleton(_ isLoading: Bool) -> some View {
        redacted(reason: isLoading ? .placeholder : [])
            .modifier(LiggaShimmer(isActive: isLoading))
            .allowsHitTesting(!isLoading)
            .accessibilityHidden(isLoading)
    }

    func liggaShimmer(_ isActive: Bool = true) -> some View {
        modifier(LiggaShimmer(isActive: isActive))
    }
}
