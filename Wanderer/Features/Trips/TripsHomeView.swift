import SwiftUI

struct TripsHomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL

    @StateObject private var store = TripsStore()
    @StateObject private var exploreStore = ExploreStore()
    @StateObject private var visitedStore = VisitedStore()

    @AppStorage(RecentTrips.storageKey) private var recentTripIDsRaw = ""

    @State private var guestTrips = GuestTripsStore.load()
    @State private var didImportGuestTrips = false
    @State private var searchText = ""
    @State private var showPlanner = false
    @State private var errorText: String?

    /// True once the first trip fetch for this session has finished, so Home
    /// shows a skeleton instead of a blank or "No trips yet" flash.
    @State private var hasLoadedTrips = false
    @State private var isFetchingTrips = false
    /// Set when the latest trip fetch failed. Shown inline with Retry.
    @State private var tripLoadError: String?

    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var memberInitials: [String] {
        let email = auth.userEmail
        guard let prefix = email.split(separator: "@").first, !prefix.isEmpty else {
            return ["LG"]
        }
        let letters = prefix.prefix(2).uppercased()
        return [String(letters)]
    }

    /// Signed in: the account trips. Guest: the trips kept on this device,
    /// with the sample trips only as a first-run starting point.
    private var allTrips: [Trip] {
        if auth.isAuthenticated {
            return store.trips.map { $0.asTrip(memberInitials: memberInitials) }
        }
        return guestTrips.isEmpty ? Trip.samples : guestTrips
    }

    private var ordering: HomeTripOrdering {
        HomeTripOrdering(trips: allTrips, recentIDs: RecentTrips.decode(recentTripIDsRaw))
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !query.isEmpty }

    private var showsTripSkeleton: Bool {
        auth.isAuthenticated
            && store.trips.isEmpty
            && tripLoadError == nil
            && (!hasLoadedTrips || isFetchingTrips)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: LiggaSpace.l) {
                    VStack(alignment: .leading, spacing: LiggaSpace.m) {
                        header
                        searchBar
                    }

                    if isSearching {
                        searchResults
                    } else {
                        homeContent
                    }
                }
                .padding(.horizontal, WandererTheme.gutter)
                .padding(.top, LiggaSpace.xs)
                .padding(.bottom, LiggaSpace.xl)
                .animation(.easeOut(duration: 0.2), value: isSearching)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .contentMargins(.bottom, LiggaSpace.l, for: .scrollContent)
            .refreshable {
                await refresh()
            }
            .navigationDestination(for: Trip.self) { trip in
                PlannerView(trip: trip)
                    .onAppear { recordOpened(trip) }
            }
            .navigationDestination(for: GuideRecord.self) { guide in
                GuideDetailView(guide: guide, store: exploreStore)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showPlanner) {
            PlanTripSheet { draft in
                createTrip(draft)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: auth.userID) {
            hasLoadedTrips = false
            tripLoadError = nil
            guard auth.isAuthenticated else { return }
            await importGuestTripsIfNeeded()
            await loadTrips()
            #if DEBUG
            await DebugSeed.runIfRequested()
            #endif
            if visitedStore.visited.isEmpty {
                await visitedStore.load()
            }
        }
        .task {
            if exploreStore.guides.isEmpty {
                await exploreStore.load()
            }
        }
        .onChange(of: store.errorMessage) { _, message in
            // Load failures are shown inline with Retry; only surface other
            // failures (create, update) as an alert.
            if let message, message != tripLoadError, !isFetchingTrips {
                errorText = message
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripsChanged)) { _ in
            Task { await loadTrips() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in
            Task { await loadTrips() }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: - Header and search

    private var header: some View {
        HStack(alignment: .center, spacing: LiggaSpace.s) {
            Text("Trips")
                .font(.ligga(.largeTitle, weight: .bold))
                .foregroundStyle(WandererTheme.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: LiggaSpace.xs)

            Button {
                LiggaHaptics.tap()
                showPlanner = true
            } label: {
                ViewThatFits(in: .horizontal) {
                    Label("New trip", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                    Image(systemName: "plus")
                        .accessibilityLabel("Plan a trip")
                }
                .font(.ligga(.subheadline, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(WandererTheme.onPrimary)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? LiggaSpace.s : LiggaSpace.m)
                .frame(minHeight: 36)
                .background(WandererTheme.primaryFill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.liggaPressable)
            .accessibilityLabel("Plan a trip")
            .accessibilityIdentifier("home-plan-trip")

            Text(memberInitials.first ?? "LG")
                .font(.ligga(.footnote, weight: .bold))
                .foregroundStyle(WandererTheme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 36, height: 36)
                .background(WandererTheme.dust, in: Circle())
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityHidden(true)
        }
    }

    private var searchBar: some View {
        HStack(spacing: LiggaSpace.xs) {
            HStack(spacing: LiggaSpace.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.ligga(.body, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
                    .accessibilityHidden(true)

                TextField("Search trips and guides", text: $searchText)
                    .font(.ligga(.body))
                    .foregroundStyle(WandererTheme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .accessibilityIdentifier("home-search")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WandererTheme.muted.opacity(0.7))
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, LiggaSpace.s)
            .frame(minHeight: 48)
            .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if searchFocused || isSearching {
                Button("Cancel") {
                    searchText = ""
                    searchFocused = false
                }
                .font(.ligga(.body))
                .foregroundStyle(WandererTheme.ink)
                .frame(minHeight: 44)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }

    // MARK: - Home content

    @ViewBuilder
    private var homeContent: some View {
        if tripLoadError != nil, allTrips.isEmpty {
            LiggaRetryCard(
                title: "Couldn't load your trips",
                message: "Check your connection and try again.",
                isRetrying: isFetchingTrips
            ) {
                Task { await loadTrips() }
            }
        } else if showsTripSkeleton {
            HomeTripsSkeleton()
                .transition(.opacity)
        } else if allTrips.isEmpty {
            firstTripState
        } else {
            if tripLoadError != nil {
                LiggaRetryCard(
                    title: "Couldn't refresh your trips",
                    message: "Showing what we had. Pull down or retry.",
                    isRetrying: isFetchingTrips
                ) {
                    Task { await loadTrips() }
                }
            }
            tripsSection(ordering)
        }

        guidesSection

        if let stayTrip = ordering.featured, stayTrip.phase != .past {
            stayCard(for: stayTrip)
        }

        if auth.isAuthenticated && !allTrips.isEmpty {
            travelStats
        }
    }

    @ViewBuilder
    private func tripsSection(_ ordering: HomeTripOrdering) -> some View {
        if let featured = ordering.featured {
            VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                Text(ordering.overline)
                    .liggaOverline()
                    .accessibilityAddTraits(.isHeader)
                HomeFeaturedTripCard(trip: featured)
            }
        }

        if !ordering.others.isEmpty {
            VStack(alignment: .leading, spacing: LiggaSpace.s) {
                SectionHeader(
                    title: ordering.featured == nil ? "All trips" : "More trips",
                    subtitle: ordering.others.count.liggaCounted("trip")
                )

                HomeGroupedCard(items: ordering.others) { trip in
                    NavigationLink(value: trip) {
                        HomeTripRow(trip: trip)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var guidesSection: some View {
        if !exploreStore.guides.isEmpty || exploreStore.isLoading {
            VStack(alignment: .leading, spacing: LiggaSpace.s) {
                SectionHeader(
                    title: "Guides for you",
                    subtitle: "Curated starting points for your next trip"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    if exploreStore.guides.isEmpty {
                        HomeGuidesSkeleton()
                            .padding(.vertical, LiggaSpace.xs)
                    } else {
                        LazyHStack(spacing: LiggaSpace.s) {
                            ForEach(exploreStore.guides.prefix(6)) { guide in
                                NavigationLink(value: guide) {
                                    HomeGuideTile(guide: guide)
                                }
                                .buttonStyle(.liggaPressable)
                            }
                        }
                        // Room for the card shadow, which a scroll view clips.
                        .padding(.vertical, LiggaSpace.xs)
                    }
                }
                .scrollDisabled(exploreStore.guides.isEmpty)
                .scrollClipDisabled()
                .padding(.vertical, -LiggaSpace.xs)
            }
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        let trips = HomeSearch.trips(allTrips, matching: query)
        let guides = HomeSearch.guides(exploreStore.guides, matching: query)

        if trips.isEmpty && guides.isEmpty {
            if showsTripSkeleton || (exploreStore.isLoading && exploreStore.guides.isEmpty) {
                HomeTripsSkeleton()
            } else {
                LiggaEmptyState(
                    icon: "magnifyingglass",
                    title: "No results for “\(query)”",
                    message: "Check the spelling, or try a city or country. You can also start a new trip there.",
                    actionTitle: "Plan a new trip"
                ) {
                    searchFocused = false
                    showPlanner = true
                }
                .accessibilityIdentifier("home-search-empty")
            }
        } else {
            Text("\((trips.count + guides.count).liggaCounted("result"))")
                .liggaOverline()
                .accessibilityAddTraits(.isHeader)

            if !trips.isEmpty {
                VStack(alignment: .leading, spacing: LiggaSpace.s) {
                    SectionHeader(title: "Your trips", subtitle: trips.count.liggaCounted("trip"))
                    HomeGroupedCard(items: trips) { trip in
                        NavigationLink(value: trip) {
                            HomeTripRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !guides.isEmpty {
                VStack(alignment: .leading, spacing: LiggaSpace.s) {
                    SectionHeader(title: "Guides", subtitle: guides.count.liggaCounted("guide"))
                    HomeGroupedCard(items: guides) { guide in
                        NavigationLink(value: guide) {
                            HomeGuideResultRow(guide: guide)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Stays and stats

    private func hotelSearchURL(for trip: Trip) -> URL? {
        var components = URLComponents(string: "https://www.booking.com/searchresults.html")
        var items = [
            URLQueryItem(name: "ss", value: trip.destination),
            URLQueryItem(name: "group_adults", value: "\(max(1, trip.members.count))"),
            URLQueryItem(name: "no_rooms", value: "1"),
            URLQueryItem(name: "group_children", value: "0")
        ]
        if let start = trip.startDate, !start.isEmpty {
            items.append(URLQueryItem(name: "checkin", value: start))
        }
        if let end = trip.endDate, !end.isEmpty {
            items.append(URLQueryItem(name: "checkout", value: end))
        }
        components?.queryItems = items
        return components?.url
    }

    private func stayCard(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: LiggaSpace.xs) {
            Button {
                LiggaHaptics.tap()
                if let url = hotelSearchURL(for: trip) { openURL(url) }
            } label: {
                HStack(spacing: LiggaSpace.s) {
                    Image(systemName: "bed.double")
                        .font(.ligga(.title3, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(WandererTheme.fillMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find a stay in \(Self.city(from: trip.destination))")
                            .font(.ligga(.headline, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(trip.dateRange) · \(max(1, trip.members.count).liggaCounted("traveller"))")
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.right")
                        .font(.ligga(.footnote, weight: .semibold))
                        .foregroundStyle(WandererTheme.muted)
                        .accessibilityHidden(true)
                }
                .padding(LiggaSpace.m)
                .liggaCard()
                .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.liggaPressable)
            .accessibilityHint("Opens Booking.com")
            .accessibilityIdentifier("home-stay-search")

            Text("Opens Booking.com with your dates. Wanderer doesn't sell stays.")
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
                .padding(.horizontal, LiggaSpace.xxs)
        }
    }

    private var travelStats: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.s) {
            SectionHeader(title: "Travel stats")

            HStack(spacing: 0) {
                statTile(value: visitedStore.countryCount, label: visitedStore.countryCount == 1 ? "country" : "countries")
                Divider().frame(height: 40)
                statTile(value: visitedStore.cityCount, label: visitedStore.cityCount == 1 ? "city" : "cities")
                Divider().frame(height: 40)
                statTile(value: allTrips.count, label: allTrips.count == 1 ? "trip" : "trips")
            }
            .padding(.vertical, LiggaSpace.m)
            .liggaCard()
        }
    }

    private func statTile(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.ligga(.title2, weight: .bold))
                .foregroundStyle(WandererTheme.ink)
                .monospacedDigit()
            Text(label)
                .font(.ligga(.footnote))
                .foregroundStyle(WandererTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var firstTripState: some View {
        VStack(spacing: LiggaSpace.m) {
            WandererMark(size: 52)
            VStack(spacing: LiggaSpace.xs) {
                Text("No trips yet")
                    .font(.ligga(.title2, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                Text("Pick a destination and Wanderer will lay out the days. You can add places, bookings and notes as you go.")
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Plan your first trip", icon: "plus") {
                showPlanner = true
            }
            .padding(.top, LiggaSpace.xxs)
            .accessibilityIdentifier("home-first-trip")
        }
        .frame(maxWidth: .infinity)
        .padding(LiggaSpace.l)
        .liggaCard()
    }

    // MARK: - Actions

    private func loadTrips() async {
        guard auth.isAuthenticated, !isFetchingTrips else { return }
        isFetchingTrips = true
        store.errorMessage = nil
        await store.load()
        tripLoadError = store.errorMessage
        hasLoadedTrips = true
        isFetchingTrips = false
    }

    private func refresh() async {
        if auth.isAuthenticated {
            await loadTrips()
            await visitedStore.load()
        }
        await exploreStore.load()
    }

    /// Copies trips made before signing in into the account, then clears the
    /// device copy so a second sign-in cannot duplicate them.
    private func importGuestTripsIfNeeded() async {
        guard !didImportGuestTrips else { return }
        didImportGuestTrips = true
        let pending = guestTrips
        guard !pending.isEmpty else { return }

        for trip in pending.reversed() {
            await store.create(trip.guestDraft)
            if store.errorMessage != nil { return }
        }
        guestTrips = []
        GuestTripsStore.clear()
    }

    private func recordOpened(_ trip: Trip) {
        let updated = RecentTrips.recording(trip.id, in: recentTripIDsRaw)
        if updated != recentTripIDsRaw {
            recentTripIDsRaw = updated
        }
    }

    private func createTrip(_ draft: NewTripDraft) {
        if auth.isAuthenticated {
            Task {
                await store.create(draft)
                if store.errorMessage == nil {
                    if let created = store.trips.first {
                        recordOpened(created.asTrip(memberInitials: memberInitials))
                    }
                    LiggaHaptics.success()
                }
            }
        } else {
            let trip = draft.asLocalTrip(memberInitials: memberInitials)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                guestTrips.insert(trip, at: 0)
            }
            GuestTripsStore.save(guestTrips)
            recordOpened(trip)
            LiggaHaptics.success()
        }
    }

    /// "Rio de Janeiro, Brazil" → "Rio de Janeiro".
    private static func city(from destination: String) -> String {
        destination.split(separator: ",").first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        } ?? destination
    }
}

#Preview {
    TripsHomeView()
        .environmentObject(AuthStore())
}
