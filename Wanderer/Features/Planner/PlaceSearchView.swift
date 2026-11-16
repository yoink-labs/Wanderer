import MapKit
import SwiftUI

/// Search Apple Maps for a place and drop it into the trip.
///
/// Results stream in from `MKLocalSearchCompleter` as the user types and are
/// biased to the trip's city, so the sheet answers "where am I going?" even
/// before the first keystroke with quick searches and real nearby places.
struct PlaceSearchView: View {
    let trip: Trip
    @ObservedObject var store: TripDetailStore
    let dayID: UUID?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    @StateObject private var model: PlaceSearchModel
    @State private var query = ""
    @State private var addingKey: String?
    @State private var errorMessage: String?
    @State private var quickResults: [MapSearchResult] = []
    @State private var quickTitle: String?
    @State private var isRunningQuickSearch = false
    @State private var forMeOnly = false

    /// Private stops are a collaboration feature; a solo guest trip already
    /// has nothing to hide from anyone.
    private var canGoPrivate: Bool { !LocalTrips.isActive }

    init(trip: Trip, store: TripDetailStore, dayID: UUID? = nil) {
        self.trip = trip
        self.store = store
        self.dayID = dayID
        _model = StateObject(wrappedValue: PlaceSearchModel(destination: trip.destination))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField
                if canGoPrivate {
                    privateToggle
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.coralDeep)
                }
            }
            .task {
                await model.prepare()
                await model.loadNearbyIfNeeded()
                try? await Task.sleep(nanoseconds: 250_000_000)
                isSearchFocused = true
            }
            .onChange(of: query) { _, newValue in
                model.query = newValue
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    quickResults = []
                    quickTitle = nil
                }
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)

            TextField("Search \(trip.destination)", text: $query)
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
        .frame(height: 48)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSearchFocused ? WandererTheme.coral.opacity(0.5) : WandererTheme.line,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Private toggle

    /// Compact: the label says what it does, the subtitle only when it is on.
    private var privateToggle: some View {
        Toggle(isOn: $forMeOnly) {
            HStack(spacing: 8) {
                Image(systemName: forMeOnly ? "person.crop.circle.fill" : "person.2")
                    .font(.ligga(.footnote, weight: .semibold))
                    .foregroundStyle(forMeOnly ? WandererTheme.coralDeep : WandererTheme.muted)
                Text(forMeOnly ? "Only I will see this stop" : "Only visible to me")
                    .font(.ligga(.footnote, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .tint(WandererTheme.coral)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("place-private-toggle")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            stateCard(
                icon: "wifi.exclamationmark",
                title: "Search unavailable",
                message: errorMessage,
                retry: true
            )
        } else if !trimmedQuery.isEmpty {
            suggestionList
        } else {
            browseContent
        }
    }

    /// Before typing: category shortcuts and real places near the trip's city.
    private var browseContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if !quickResults.isEmpty {
                    HStack {
                        Text(quickTitle ?? "Nearby")
                            .font(.ligga(.footnote, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                        Spacer()
                        Button("Clear") {
                            quickResults = []
                            quickTitle = nil
                        }
                        .font(.ligga(.footnote, weight: .semibold))
                        .foregroundStyle(WandererTheme.accentText)
                    }
                    resultRows(quickResults)
                } else {
                    Text("Search near \(trip.destination)")
                        .font(.ligga(.footnote, weight: .semibold))
                        .foregroundStyle(WandererTheme.muted)

                    quickChips

                    if !model.nearby.isEmpty {
                        Text("Popular near \(trip.destination)")
                            .font(.ligga(.footnote, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                            .padding(.top, 2)
                        resultRows(model.nearby)
                    } else if model.isLoadingNearby {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(WandererTheme.coral)
                            Text("Finding places near \(trip.destination)…")
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }

                    Text("Results from Apple Maps")
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var quickChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(PlaceSearchModel.quickSearches, id: \.title) { item in
                Button {
                    Task { await runQuickSearch(item.title, item.query) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol)
                            .font(.ligga(.caption, weight: .semibold))
                        Text(item.title)
                            .font(.ligga(.footnote, weight: .semibold))
                            .lineLimit(1)
                        if isRunningQuickSearch && quickTitle == item.title {
                            Spacer(minLength: 0)
                            ProgressView().controlSize(.mini).tint(WandererTheme.coralDeep)
                        }
                    }
                    .foregroundStyle(WandererTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WandererTheme.card, in: Capsule())
                    .overlay(Capsule().stroke(WandererTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestionList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(model.suggestions) { suggestion in
                    Button {
                        Task { await add(suggestion) }
                    } label: {
                        suggestionRow(suggestion)
                    }
                    .buttonStyle(.plain)
                    .disabled(addingKey != nil)
                }

                if model.suggestions.isEmpty && !model.isResolving {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(WandererTheme.coral)
                        Text("Searching Apple Maps…")
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }

                Text("Results from Apple Maps")
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted.opacity(0.9))
                    .padding(.top, 6)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func suggestionRow(_ suggestion: PlaceSearchModel.Suggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WandererTheme.coralSoft)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if model.isResolving {
                ProgressView().controlSize(.small).tint(WandererTheme.coral)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(WandererTheme.accentText)
            }
        }
        .padding(10)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WandererTheme.line.opacity(0.75), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func resultRows(_ results: [MapSearchResult]) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(results) { result in
                Button {
                    Task { await add(result) }
                } label: {
                    resultRow(result)
                }
                .buttonStyle(.plain)
                .disabled(addingKey != nil)
            }
        }
    }

    private func resultRow(_ result: MapSearchResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WandererTheme.coralSoft)
                Image(systemName: result.category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                if let address = result.address, !address.isEmpty {
                    Text(address)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if addingKey == key(for: result) {
                ProgressView().controlSize(.small).tint(WandererTheme.coral)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(WandererTheme.accentText)
            }
        }
        .padding(10)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WandererTheme.line.opacity(0.75), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stateCard(
        icon: String,
        title: String,
        message: String,
        retry: Bool = false
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle().fill(WandererTheme.coralSoft)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 58, height: 58)

            Text(title)
                .wandererHeading(.section)
                .foregroundStyle(WandererTheme.ink)

            Text(message)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if retry {
                Button {
                    errorMessage = nil
                    model.query = trimmedQuery
                } label: {
                    Text("Try again")
                        .font(.ligga(.subheadline, weight: .bold))
                        .foregroundStyle(WandererTheme.coralDeep)
                        .padding(.horizontal, 18)
                        .frame(minHeight: WandererTheme.minimumTarget)
                        .background(WandererTheme.card, in: Capsule())
                        .overlay(Capsule().stroke(WandererTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func key(for result: MapSearchResult) -> String {
        "\(result.name.lowercased())|\(String(format: "%.4f,%.4f", result.latitude, result.longitude))"
    }

    private func runQuickSearch(_ title: String, _ query: String) async {
        guard !isRunningQuickSearch else { return }
        isRunningQuickSearch = true
        quickTitle = title
        defer { isRunningQuickSearch = false }
        quickResults = await model.runQuickSearch(query)
        if quickResults.isEmpty {
            quickTitle = nil
            errorMessage = "Apple Maps didn't return any \(title.lowercased()) near \(trip.destination)."
        }
    }

    private func add(_ suggestion: PlaceSearchModel.Suggestion) async {
        guard addingKey == nil else { return }
        // Reserve the row so a double tap can't fire twice, then resolve.
        addingKey = "resolving|\(suggestion.title.lowercased())"
        isSearchFocused = false

        defer { addingKey = nil }
        guard let result = await model.resolve(suggestion) else { return }
        await performAdd(result)
    }

    private func add(_ result: MapSearchResult) async {
        guard addingKey == nil else { return }
        addingKey = key(for: result)
        isSearchFocused = false
        defer { addingKey = nil }
        await performAdd(result)
    }

    /// Adds the stop (deduplicated by the store) and closes the sheet.
    private func performAdd(_ result: MapSearchResult) async {
        if forMeOnly {
            await store.addPrivatePlaceIfNew(
                name: result.name,
                address: result.address,
                latitude: result.latitude,
                longitude: result.longitude,
                category: result.category,
                dayID: dayID
            )
        } else {
            await store.addPlaceIfNew(
                name: result.name,
                address: result.address,
                latitude: result.latitude,
                longitude: result.longitude,
                category: result.category,
                dayID: dayID,
                website: result.website,
                phone: result.phone
            )
        }
        dismiss()
    }
}

#Preview {
    PlaceSearchView(
        trip: Trip.samples[0],
        store: TripDetailStore(trip: Trip.samples[0])
    )
}
