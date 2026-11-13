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

/// The one hero on Home: a photo postcard for the featured trip, with the
/// route spine along the bottom showing where today sits in the trip.
struct HomeFeaturedTripCard: View {
    let trip: Trip
    var overline: String = ""
    var transitionNamespace: Namespace.ID?

    @ScaledMetric(relativeTo: .title2) private var scaledHeight: CGFloat = 300
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var height: CGFloat { min(max(scaledHeight, 300), 440) }
    private var progress: TripRouteProgress { TripRouteProgress(trip: trip) }

    var body: some View {
        NavigationLink(value: trip) {
            ZStack(alignment: .bottomLeading) {
                HomeTripCover(trip: trip)

                LinearGradient(
                    stops: [
                        .init(color: WandererTheme.charcoal.opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: WandererTheme.charcoal.opacity(0.92), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    if !overline.isEmpty {
                        Text(overline)
                            .font(.ligga(.footnote, weight: .bold))
                            .foregroundStyle(WandererTheme.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0xF2A922), in: Capsule())
                    }

                    Spacer(minLength: LiggaSpace.l)

                    Text(trip.title)
                        .font(.display(.title, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    Text(trip.destination)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.top, 2)

                    TripRouteSpine(progress: progress)
                        .padding(.top, LiggaSpace.m)

                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(trip.dateRange)
                            Spacer(minLength: LiggaSpace.xs)
                            Text(progress.label)
                            if trip.places > 0 {
                                Text(trip.places.liggaCounted("place"))
                                    .padding(.leading, LiggaSpace.xs)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.dateRange)
                            Text(progress.label)
                            if trip.places > 0 {
                                Text(trip.places.liggaCounted("place"))
                            }
                        }
                    }
                    .font(.ligga(.footnote, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.top, LiggaSpace.xs)
                }
                .padding(LiggaSpace.l - 4)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: WandererTheme.postcardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.postcardRadius, style: .continuous))
            .modifier(TripTransitionSource(id: trip.id, namespace: transitionNamespace))
        }
        .buttonStyle(.liggaPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(overline.isEmpty ? "" : overline + ", ")\(trip.title), \(trip.destination), \(trip.dateRange), \(progress.label)")
        .accessibilityHint("Opens the planner")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home-featured-trip")
    }
}

/// The signature element: a marigold route with one bead per day. Days behind
/// you are filled, today is a larger ringed bead, days ahead are hollow.
/// Long trips draw a continuous progress bar instead of beads.
struct TripRouteSpine: View {
    let progress: TripRouteProgress
    var lineColor: Color = Color(hex: 0xF2A922)
    var restColor: Color = .white.opacity(0.35)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let count = progress.dayCount
            let fraction = count <= 1
                ? (progress.completed > 0 ? 1 : 0)
                : CGFloat(progress.current ?? (progress.completed >= count ? count - 1 : 0)) / CGFloat(count - 1)
            ZStack(alignment: .leading) {
                Capsule().fill(restColor).frame(height: 3)
                Capsule().fill(lineColor)
                    .frame(width: max(0, width * (progress.completed == 0 && progress.current == nil ? 0 : fraction)), height: 3)

                if progress.showsBeads {
                    ForEach(0..<count, id: \.self) { index in
                        bead(index)
                            .position(
                                x: count <= 1 ? 6 : 6 + (width - 12) * CGFloat(index) / CGFloat(count - 1),
                                y: proxy.size.height / 2
                            )
                    }
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bead(_ index: Int) -> some View {
        if index == progress.current {
            Circle()
                .fill(lineColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
        } else if index < progress.completed {
            Circle().fill(lineColor).frame(width: 8, height: 8)
        } else {
            Circle()
                .strokeBorder(.white.opacity(0.75), lineWidth: 2)
                .background(Circle().fill(WandererTheme.charcoal.opacity(0.6)))
                .frame(width: 9, height: 9)
        }
    }
}

/// Marks a trip card as the source of the zoom transition into the planner.
struct TripTransitionSource: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// A trip row for use inside a single grouped card. No background of its own.
struct HomeTripRow: View {
    let trip: Trip

    @ScaledMetric(relativeTo: .headline) private var thumbSize: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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


            Text(countdown)
                .font(.ligga(.footnote, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(trip.phase == .past ? WandererTheme.muted : WandererTheme.accentText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LiggaSpace.m)
        .padding(.vertical, LiggaSpace.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// Short trailing cue: how far away the trip is, or where you are in it.
    private var countdown: String {
        switch trip.phase {
        case .inProgress:
            return TripRouteProgress(trip: trip).label
        case .past:
            return "Past"
        case .upcoming:
            guard let start = TripDayRecord.date(from: trip.startDate) else { return "" }
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: Date()), to: start
            ).day ?? 0
            return days <= 1 ? (days <= 0 ? "Today" : "Tomorrow") : "In \(days) d"
        }
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

/// Compact trip card for the two-/three-column grid on a wide canvas
/// (iPhone Duo open, iPad, Split View). The featured trip keeps the large
/// postcard; everything else becomes one of these.
struct HomeTripTile: View {
    let trip: Trip

    @Environment(\.colorScheme) private var scheme

    private var countdown: String {
        switch trip.phase {
        case .inProgress:
            return TripRouteProgress(trip: trip).label
        case .past:
            return "Past"
        case .upcoming:
            guard let start = TripDayRecord.date(from: trip.startDate) else { return "" }
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: Date()), to: start
            ).day ?? 0
            return days <= 1 ? (days <= 0 ? "Today" : "Tomorrow") : "In \(days) d"
        }
    }

    var body: some View {
        NavigationLink(value: trip) {
            VStack(alignment: .leading, spacing: 0) {
                HomeTripCover(trip: trip)
                    .frame(height: 152)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 20,
                        style: .continuous
                    ))

                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.title)
                        .font(.ligga(.headline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(trip.destination)
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(trip.dateRange)
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(countdown)
                            .font(.ligga(.caption, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(
                                trip.phase == .past || trip.phase == .upcoming
                                    ? WandererTheme.muted
                                    : WandererTheme.accentText
                            )
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(WandererTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: WandererTheme.cardShadow(scheme), radius: scheme == .dark ? 0 : 12, x: 0, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.liggaPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trip.title), \(trip.destination), \(trip.dateRange)")
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
