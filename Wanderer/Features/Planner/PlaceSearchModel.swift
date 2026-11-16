import MapKit
import SwiftUI

/// Everything the "Add a place" sheet needs: Apple Maps completions as you
/// type, quick category searches for the trip's city, and a resolver that turns
/// a tapped suggestion into a real coordinate to add.
///
/// `MKLocalSearchCompleter` is what makes this feel like Apple Maps: results
/// arrive per keystroke instead of one slow request per word, and they are
/// biased to the trip's destination so "Obelisco" in a Buenos Aires trip is
/// the one on Avenida 9 de Julio, not one in Mexico.
@MainActor
final class PlaceSearchModel: NSObject, ObservableObject {
    struct Suggestion: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion

        static func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
            lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(subtitle)
        }
    }

    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var nearby: [MapSearchResult] = []
    @Published private(set) var isLoadingNearby = false
    @Published private(set) var isResolving = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private let destination: String
    private var region: MKCoordinateRegion?
    private var loadedNearbyFor: String?

    /// Category shortcuts shown before the first keystroke. Each one is a real
    /// local search near the destination, so the sheet is useful immediately.
    static let quickSearches: [(title: String, symbol: String, query: String)] = [
        ("Restaurants", "fork.knife", "restaurants"),
        ("Cafés", "cup.and.saucer.fill", "cafes"),
        ("Museums", "building.columns.fill", "museums"),
        ("Things to do", "star.fill", "things to do"),
    ]

    init(destination: String) {
        self.destination = destination
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var query: String = "" {
        didSet {
            errorMessage = nil
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 2 {
                completer.cancel()
                suggestions = []
                isSearching = false
                return
            }
            isSearching = true
            completer.queryFragment = trimmed
        }
    }

    /// A last-resort exact search when the completer has nothing. Apple's
    /// completer is fast but occasionally returns nothing for an unusual
    /// spelling; this searches the whole map once and keeps the sheet usable.
    func searchEverywhere(_ query: String) async -> [MapSearchResult] {
        isSearching = true
        defer { isSearching = false }
        await prepare()
        return (try? await MapSearchService.search(query, near: region?.center)) ?? []
    }

    /// Bias every search to the trip's city. Called once when the sheet opens.
    func prepare() async {
        guard region == nil else { return }
        guard let coordinate = await DestinationLocator.coordinate(for: destination) else { return }
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 45_000,
            longitudinalMeters: 45_000
        )
        self.region = region
        completer.region = region
    }

    /// Real places near the destination, shown before the user types.
    func loadNearbyIfNeeded() async {
        guard loadedNearbyFor != destination else { return }
        loadedNearbyFor = destination
        isLoadingNearby = true
        defer { isLoadingNearby = false }

        await prepare()
        let near = region?.center
        let results = (try? await MapSearchService.search("things to do", near: near)) ?? []
        nearby = Array(results.prefix(6))
    }

    func runQuickSearch(_ query: String) async -> [MapSearchResult] {
        await prepare()
        return (try? await MapSearchService.search(query, near: region?.center)) ?? []
    }

    /// Turn a tapped Apple Maps suggestion into a place we can add.
    func resolve(_ suggestion: Suggestion) async -> MapSearchResult? {
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request(completion: suggestion.completion)
        if let region { request.region = region }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }
            let name = item.name ?? suggestion.title
            let placemark = item.placemark
            return MapSearchResult(
                name: name,
                address: placemark.title,
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude,
                phone: item.phoneNumber,
                website: item.url?.absoluteString,
                category: MapSearchService.category(for: item.pointOfInterestCategory)
            )
        } catch {
            // Fall back to the text we already have so a slow resolve never
            // leaves the tap doing nothing.
            errorMessage = "Apple Maps didn't return details for that place. Try the next suggestion."
            return nil
        }
    }
}

extension PlaceSearchModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.prefix(12).map {
            Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
        Task { @MainActor in
            self.suggestions = mapped
            self.errorMessage = nil
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
            // A cancelled request is normal while typing; don't shout about it.
            if (error as NSError).code == NSURLErrorCancelled { return }
            self.suggestions = []
        }
    }
}
