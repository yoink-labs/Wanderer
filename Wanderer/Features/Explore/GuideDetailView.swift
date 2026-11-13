import SwiftUI

struct GuideDetailView: View {
    let guide: GuideRecord
    @ObservedObject var store: ExploreStore

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var tripsStore = TripsStore()
    @AppStorage("wanderer.isGuest") private var isGuest = false

    @State private var isRequestingPlaces = false
    @State private var copyState: CopyState = .idle
    @State private var copySuccessCount = 0
    @State private var copyFailureCount = 0
    /// Set once `TripsStore.create` succeeds, so a retry after a failed stop
    /// copy reuses that trip instead of creating a duplicate.
    @State private var createdTripID: UUID?
    @State private var createdTripTitle = ""

    private let gutter: CGFloat = 16

    private enum CopyState: Equatable {
        case idle
        case copying
        case copied(tripTitle: String)
        case failed(String)
    }

    private var places: [GuidePlaceRecord] {
        store.placesByGuide[guide.id] ?? []
    }

    private var canCopy: Bool {
        !isGuest && !places.isEmpty && !isRequestingPlaces && copyState != .copying
            && auth.isAuthenticated
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                cover

                if let summary = guide.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.ligga(.body))
                        .foregroundStyle(WandererTheme.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .liggaCard()
                }

                if let destination = guide.destination, !destination.isEmpty {
                    infoChip(icon: "mappin", text: destination)
                }

                placesSection
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, 32)
        }
        .background(WandererTheme.sand.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            copyBar
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: copySuccessCount)
        .sensoryFeedback(.error, trigger: copyFailureCount)
        .task {
            guard store.placesByGuide[guide.id] == nil else { return }
            isRequestingPlaces = true
            await store.loadPlaces(for: guide.id)
            isRequestingPlaces = false
        }
    }

    // MARK: - Copy to my trips

    private var copyBar: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = copyState {
                Text(message)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.coralDeep)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if let hint = copyHint {
                Text(hint)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button {
                Task { await copyToTrips() }
            } label: {
                HStack(spacing: 8) {
                    if copyState == .copying {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: copyButtonIcon)
                    }
                    Text(copyButtonTitle)
                }
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    canCopy || isCopied ? WandererTheme.ink : WandererTheme.ink.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canCopy || isCopied)
            .accessibilityIdentifier("guide-copy-to-trips")
            .accessibilityHint(copyHint ?? "Creates a new trip with every stop in this guide.")
        }
        .padding(.horizontal, gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(WandererTheme.sand.opacity(0.96).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(WandererTheme.line.opacity(0.6)).frame(height: 1)
        }
    }

    private var isCopied: Bool {
        if case .copied = copyState { return true }
        return false
    }

    private var copyButtonTitle: String {
        switch copyState {
        case .copying: return "Copying…"
        case .copied: return "Added to your trips"
        case .failed: return "Try copying again"
        case .idle: return "Copy to my trips"
        }
    }

    private var copyButtonIcon: String {
        isCopied ? "checkmark" : "plus.square.on.square"
    }

    private var copyHint: String? {
        if case .copied(let title) = copyState {
            return "“\(title)” is on your Trips tab with \(places.count) \(places.count == 1 ? "stop" : "stops") to schedule."
        }
        if isGuest || !auth.isAuthenticated {
            return "Sign in to copy guides into your trips."
        }
        if !isRequestingPlaces && places.isEmpty {
            return "This guide has no stops to copy yet."
        }
        return nil
    }

    /// Creates a trip with `TripsStore.create`, then copies the guide's stops in
    /// as unscheduled places. `create` reports failure through `errorMessage` and
    /// inserts the new record at the front of `trips`, which is how the new id is read.
    private func copyToTrips() async {
        guard canCopy else { return }
        copyState = .copying

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let days = max(1, min(7, (places.count + 3) / 4))
        let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
        let trimmedDestination = guide.destination?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let draft = NewTripDraft(
            title: guide.title,
            destination: trimmedDestination.isEmpty ? guide.title : trimmedDestination,
            startDate: start,
            endDate: end,
            days: days,
            dateRange: "\(formatter.string(from: start)) – \(formatter.string(from: end))",
            coverColor: "D77A61",
            timezone: TimeZone.current.identifier
        )

        if createdTripID == nil {
            await tripsStore.create(draft)

            if let message = tripsStore.errorMessage {
                fail(message)
                return
            }
            guard let trip = tripsStore.trips.first, trip.title == draft.title else {
                fail("Couldn't find the new trip. Check your Trips tab before trying again.")
                return
            }
            createdTripID = trip.id
            createdTripTitle = trip.title
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        }

        guard let tripID = createdTripID else { return }

        do {
            try await store.copyPlaces(places, intoTrip: tripID)
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
            copyState = .copied(tripTitle: createdTripTitle)
            copySuccessCount += 1
        } catch {
            fail("“\(createdTripTitle)” was created, but its stops couldn't be copied. Try again to add them.")
        }
    }

    private func fail(_ message: String) {
        copyState = .failed(message)
        copyFailureCount += 1
    }

    // MARK: - Cover

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay { GuideCoverImage(guide: guide) }
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: WandererTheme.charcoal.opacity(0.8), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                if let destination = guide.destination, !destination.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                        Text(destination)
                    }
                    .font(.ligga(.subheadline, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                }

                Text(guide.title)
                    .wandererHeading(.hero)
                    .foregroundStyle(.white)
                    .lineLimit(nil)
            }
            .padding(20)
        }
        .frame(minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Places

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Along the way",
                subtitle: places.isEmpty ? "Stops in this guide" : "\(places.count) \(places.count == 1 ? "stop" : "stops")"
            )

            if isRequestingPlaces {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(WandererTheme.coral)
                    Text("Loading places…")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else if let message = store.errorMessage, places.isEmpty {
                placesError(message)
            } else if places.isEmpty {
                emptyPlaces
            } else {
                ForEach(Array(places.enumerated()), id: \.element.id) { item in
                    GuidePlaceCard(index: item.offset, place: item.element)
                }
            }
        }
    }

    private var emptyPlaces: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.ligga(.title, weight: .semibold))
                .foregroundStyle(WandererTheme.muted.opacity(0.6))
            Text("No stops added yet")
                .wandererHeading(.section)
                .foregroundStyle(WandererTheme.ink)
            Text("This guide is still being mapped out.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
    }

    private func placesError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ligga(.title2, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
            Text(message)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await retryPlaces() }
            } label: {
                Text("Try again")
                    .font(.ligga(.subheadline, weight: .bold))
                    .foregroundStyle(WandererTheme.onPrimary)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(WandererTheme.primaryFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(WandererTheme.coralSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func retryPlaces() async {
        store.errorMessage = nil
        isRequestingPlaces = true
        await store.loadPlaces(for: guide.id)
        isRequestingPlaces = false
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
            Text(text)
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(WandererTheme.card, in: Capsule())
        .overlay(Capsule().stroke(WandererTheme.line, lineWidth: 1))
    }
}

// MARK: - Place card

private struct GuidePlaceCard: View {
    let index: Int
    let place: GuidePlaceRecord

    private var photoURL: URL? {
        guard let photoUrl = place.photoUrl,
              !photoUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: photoUrl) else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(WandererTheme.onAccent)
                    .frame(width: 28, height: 28)
                    .background(WandererTheme.route, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .wandererHeading(.card)
                        .foregroundStyle(WandererTheme.ink)

                    if let address = place.address, !address.isEmpty {
                        Label(address, systemImage: "mappin")
                            .font(.ligga(.caption))
                            .foregroundStyle(WandererTheme.muted)
                    }
                }

                Spacer(minLength: 0)
            }

            if let notes = place.notes, !notes.isEmpty {
                Text(notes)
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if phase.error != nil {
                        ZStack {
                            LinearGradient(
                                colors: [WandererTheme.sandDeep, WandererTheme.coralSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "photo")
                                .font(.ligga(.title2, weight: .semibold))
                                .foregroundStyle(WandererTheme.muted.opacity(0.5))
                        }
                    } else {
                        ZStack {
                            WandererTheme.sandDeep
                            ProgressView()
                                .tint(WandererTheme.coral)
                        }
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .liggaCard()
    }
}

#Preview {
    NavigationStack {
        GuideDetailView(
            guide: GuideRecord(
                id: UUID(),
                authorId: nil,
                title: "48 hours in Kyoto",
                summary: "A first-timer's route through shrines, coffee and the Kamo river.",
                destination: "Kyoto, Japan",
                coverUrl: nil,
                isPublished: true
            ),
            store: ExploreStore()
        )
    }
}
