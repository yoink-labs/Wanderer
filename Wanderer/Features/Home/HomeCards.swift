import SwiftUI

/// Trip photo: the trip's own cover, else a curated destination photo. Shows a
/// quiet fill while loading and the trip palette if the image fails.
struct HomeTripCover: View {
    let trip: Trip

    private var url: URL? {
        if let coverUrl = trip.coverUrl, let url = URL(string: coverUrl) {
            return url
        }
        return ImageCatalog.cover(for: trip.destination)
    }

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        LinearGradient(
                            colors: trip.palette.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    default:
                        WandererTheme.fillMuted
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// The one hero on Home: a photo card for the featured trip.
struct HomeFeaturedTripCard: View {
    let trip: Trip

    @ScaledMetric(relativeTo: .title2) private var scaledHeight: CGFloat = 200

    private var height: CGFloat { min(max(scaledHeight, 200), 300) }

    private var metaLine: String {
        var parts = [trip.dateRange, trip.days.liggaCounted("day")]
        if trip.places > 0 {
            parts.append(trip.places.liggaCounted("place"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(value: trip) {
            ZStack(alignment: .bottomLeading) {
                HomeTripCover(trip: trip)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: WandererTheme.charcoal.opacity(0.85), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                    if trip.phase == .inProgress {
                        LiggaStatusChip(title: "In progress", tone: .strong)
                            .padding(.bottom, LiggaSpace.xxs)
                    }
                    Text(trip.title)
                        .font(.ligga(.title2, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(trip.destination)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.ligga(.footnote, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(LiggaSpace.m)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
            .shadow(color: WandererTheme.cardShadow, radius: 10, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.liggaPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trip.title), \(trip.destination), \(metaLine)")
        .accessibilityHint("Opens the planner")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home-featured-trip")
    }
}

/// A trip row for use inside a single grouped card. No background of its own.
struct HomeTripRow: View {
    let trip: Trip

    @ScaledMetric(relativeTo: .headline) private var thumbSize: CGFloat = 56

    private var dateLine: String {
        "\(trip.dateRange) · \(trip.days.liggaCounted("day"))"
    }

    var body: some View {
        HStack(spacing: LiggaSpace.s) {
            HomeTripCover(trip: trip)
                .frame(width: min(thumbSize, 80), height: min(thumbSize, 80))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title)
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(trip.destination)
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LiggaSpace.xs) {
                        dateText
                        statusChip
                    }
                    VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                        dateText
                        statusChip
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if trip.members.count > 1 {
                AvatarStack(initials: Array(trip.members.prefix(3)), size: 24)
                    .accessibilityHidden(true)
            }

            Image(systemName: "chevron.right")
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.muted.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LiggaSpace.m)
        .padding(.vertical, LiggaSpace.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var dateText: some View {
        Text(dateLine)
            .font(.ligga(.footnote))
            .foregroundStyle(WandererTheme.muted)
            .lineLimit(1)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch trip.phase {
        case .inProgress:
            LiggaStatusChip(title: "In progress", tone: .strong)
        case .past:
            LiggaStatusChip(title: "Past", tone: .quiet)
        case .upcoming:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        var text = "\(trip.title), \(trip.destination), \(dateLine)"
        switch trip.phase {
        case .inProgress: text += ", in progress"
        case .past: text += ", past trip"
        case .upcoming: break
        }
        return text
    }
}

/// Horizontal carousel tile for a published guide.
struct HomeGuideTile: View {
    let guide: GuideRecord

    static let width: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GuideCoverImage(guide: guide)
                .frame(width: Self.width, height: 96)
                .clipped()

            VStack(alignment: .leading, spacing: LiggaSpace.xxs) {
                Text(guide.title)
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                Label(guide.destination?.isEmpty == false ? guide.destination! : "Guide", systemImage: "mappin")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(1)
            }
            .padding(LiggaSpace.s)
            .frame(width: Self.width, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        .liggaCard()
        .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([guide.title, guide.destination].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the guide")
        .accessibilityAddTraits(.isButton)
    }
}

/// Guide row for search results, styled to sit in the same grouped card as
/// `HomeTripRow`.
struct HomeGuideResultRow: View {
    let guide: GuideRecord

    @ScaledMetric(relativeTo: .headline) private var thumbSize: CGFloat = 56

    var body: some View {
        HStack(spacing: LiggaSpace.s) {
            GuideCoverImage(guide: guide)
                .frame(width: min(thumbSize, 80), height: min(thumbSize, 80))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let destination = guide.destination, !destination.isEmpty {
                    Text(destination)
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                }
                LiggaStatusChip(title: "Guide", tone: .quiet)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.muted.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LiggaSpace.m)
        .padding(.vertical, LiggaSpace.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guide: \([guide.title, guide.destination].compactMap { $0 }.joined(separator: ", "))")
        .accessibilityAddTraits(.isButton)
    }
}

/// Stacks rows inside one card with hairlines inset to the text edge.
struct HomeGroupedCard<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 {
                    Divider()
                        .overlay(WandererTheme.line.opacity(0.6))
                        .padding(.leading, LiggaSpace.m + 56 + LiggaSpace.s)
                }
            }
        }
        .liggaCard()
    }
}
