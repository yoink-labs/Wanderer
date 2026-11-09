import MapKit
import SwiftUI

/// Search Apple Maps for a place and drop it into the trip.
struct PlaceSearchView: View {
    let trip: Trip
    @ObservedObject var store: TripDetailStore
    let dayID: UUID?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    @State private var query = ""
    @State private var results: [MapSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var addingID: UUID?

    init(trip: Trip, store: TripDetailStore, dayID: UUID? = nil) {
        self.trip = trip
        self.store = store
        self.dayID = dayID
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                searchField
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                isSearchFocused = true
            }
            .task(id: query) {
                await search()
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)

            TextField("Search museums, cafés, addresses", text: $query)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.ink)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityIdentifier("place-search-field")

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WandererTheme.muted.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, query.isEmpty ? 15 : 3)
        .frame(height: 50)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSearchFocused ? WandererTheme.coral.opacity(0.5) : WandererTheme.line,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isSearching {
            stateCard(
                icon: "sparkle.magnifyingglass",
                title: "Searching Apple Maps…",
                message: "Looking near \(trip.destination).",
                showsProgress: true
            )
        } else if let errorMessage {
            stateCard(
                icon: "wifi.exclamationmark",
                title: "Search unavailable",
                message: errorMessage,
                retry: true
            )
        } else if trimmedQuery.isEmpty {
            stateCard(
                icon: "magnifyingglass",
                title: "Find somewhere to go",
                message: "Search for a museum, café or exact address to add it to \(trip.title)."
            )
        } else if results.isEmpty {
            stateCard(
                icon: "mappin.slash",
                title: "No places found",
                message: "Try a different name, or search for the street and city instead."
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 9) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        Task { await add(result) }
                    } label: {
                        resultRow(result)
                    }
                    .buttonStyle(.plain)
                    .disabled(addingID != nil)
                    .accessibilityIdentifier("place-search-add-\(index)")
                }

                Text("Results from Apple Maps")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .padding(.top, 6)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func resultRow(_ result: MapSearchResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WandererTheme.coralSoft)
                Image(systemName: result.category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)

                if let address = result.address, !address.isEmpty {
                    Text(address)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(result.category.title)
                    .font(.ligga(.caption, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
            }

            Spacer(minLength: 6)

            addBadge(for: result)
        }
        .padding(11)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WandererTheme.line.opacity(0.75), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func addBadge(for result: MapSearchResult) -> some View {
        if addingID == result.id {
            ProgressView()
                .tint(WandererTheme.coral)
                .frame(width: 64, height: 34)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.ligga(.caption, weight: .bold))
                Text("Add")
                    .font(.ligga(.caption, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(WandererTheme.charcoal, in: Capsule())
        }
    }

    private func stateCard(
        icon: String,
        title: String,
        message: String,
        showsProgress: Bool = false,
        retry: Bool = false
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()

            if showsProgress {
                ProgressView()
                    .tint(WandererTheme.coral)
                    .scaleEffect(1.1)
            } else {
                ZStack {
                    Circle()
                        .fill(WandererTheme.coralSoft)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WandererTheme.coralDeep)
                }
                .frame(width: 58, height: 58)
            }

            Text(title)
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)

            Text(message)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if retry {
                Button {
                    Task { await search() }
                } label: {
                    Text("Try again")
                        .font(.ligga(.subheadline, weight: .bold))
                        .foregroundStyle(WandererTheme.coralDeep)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(WandererTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nearCoordinate: CLLocationCoordinate2D? {
        guard let coordinate = store.places.compactMap(\.coordinate).first else { return nil }
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func search() async {
        let trimmed = trimmedQuery
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            // Debounce so we only hit Apple Maps once typing settles.
            try await Task.sleep(nanoseconds: 300_000_000)
            let found = try await MapSearchService.search(trimmed, near: nearCoordinate)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = "We couldn't reach Apple Maps. Check your connection and try again."
            isSearching = false
        }
    }

    private func add(_ result: MapSearchResult) async {
        guard addingID == nil else { return }
        addingID = result.id

        await store.addPlace(
            name: result.name,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            category: result.category,
            dayID: dayID,
            website: result.website,
            phone: result.phone
        )

        addingID = nil
        dismiss()
    }
}

#Preview {
    PlaceSearchView(
        trip: Trip.samples[0],
        store: TripDetailStore(trip: Trip.samples[0])
    )
}
