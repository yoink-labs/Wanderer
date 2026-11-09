import SwiftUI

/// Placeholder for the trips area while the first load is in flight, shaped
/// like the real hero and grouped list so nothing jumps when data lands.
struct HomeTripsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.l) {
            VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                SkeletonBlock(width: 120, height: 12)
                SkeletonBlock(height: 200, radius: WandererTheme.cardRadius)
            }

            VStack(alignment: .leading, spacing: LiggaSpace.s) {
                SkeletonBlock(width: 110, height: 20)
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { index in
                        row
                        if index == 0 {
                            Divider().padding(.leading, LiggaSpace.m + 56 + LiggaSpace.s)
                        }
                    }
                }
                .liggaCard()
            }
        }
        .liggaShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your trips")
        .accessibilityIdentifier("home-trips-skeleton")
    }

    private var row: some View {
        HStack(spacing: LiggaSpace.s) {
            SkeletonBlock(width: 56, height: 56, radius: 10)
            VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                SkeletonBlock(width: 160, height: 14)
                SkeletonBlock(width: 110, height: 12)
                SkeletonBlock(width: 90, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LiggaSpace.m)
        .padding(.vertical, LiggaSpace.s)
    }
}

/// Placeholder carousel for guides.
struct HomeGuidesSkeleton: View {
    var body: some View {
        HStack(spacing: LiggaSpace.s) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(WandererTheme.fillMuted)
                        .frame(width: HomeGuideTile.width, height: 132)
                    VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                        SkeletonBlock(width: 170, height: 14)
                        SkeletonBlock(width: 100, height: 12)
                    }
                    .padding(LiggaSpace.s)
                    .frame(width: HomeGuideTile.width, alignment: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
                .liggaCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liggaShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading guides")
    }
}
