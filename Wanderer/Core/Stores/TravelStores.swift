import Foundation

@MainActor
final class ExploreStore: ObservableObject {
    @Published private(set) var guides: [GuideRecord] = []
    @Published private(set) var placesByGuide: [UUID: [GuidePlaceRecord]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var api: WandererAPI? { CloudSession.shared.api }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            guides = try await api.guides()
        } catch {
            errorMessage = "Couldn't load guides: \(error.localizedDescription)"
        }
    }

    func loadPlaces(for guideID: UUID) async {
        guard placesByGuide[guideID] == nil, let api else { return }
        do {
            placesByGuide[guideID] = try await api.guidePlaces(guideID: guideID)
        } catch {
            errorMessage = "Couldn't load this guide: \(error.localizedDescription)"
        }
    }

    /// Copies a guide's stops into an existing trip as unscheduled places, in
    /// guide order.
    func copyPlaces(_ places: [GuidePlaceRecord], intoTrip tripID: UUID) async throws {
        guard !places.isEmpty, let api else { return }
        let rows = places
            .sorted { $0.position < $1.position }
            .enumerated()
            .map { offset, place -> [String: JSONValue] in
                [
                    "name": .string(place.name),
                    "address": .optional(place.address),
                    "lat": .optional(place.lat),
                    "lng": .optional(place.lng),
                    "notes": .optional(place.notes),
                    "photo_url": .optional(place.photoUrl),
                    "position": .integer(offset)
                ]
            }
        _ = try await api.addPlaces(tripID: tripID, rows: rows)
    }
}

@MainActor
final class VisitedStore: ObservableObject {
    @Published private(set) var visited: [VisitedPlaceRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var api: WandererAPI? { CloudSession.shared.api }

    var countryCount: Int {
        Set(visited.map(\.countryCode)).count
    }

    var cityCount: Int {
        Set(visited.compactMap { $0.city?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty }).count
    }

    /// Unique visited country codes, most recently visited first.
    var countryCodes: [String] {
        var seen = Set<String>()
        return visited
            .sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            .map { $0.countryCode.uppercased() }
            .filter { seen.insert($0).inserted }
    }

    var earliestYear: Int? {
        visited.compactMap(\.year).min()
    }

    func load() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            visited = try await api.visitedPlaces()
        } catch {
            errorMessage = "Couldn't load visited places: \(error.localizedDescription)"
        }
    }

    func add(countryCode: String, city: String?, year: Int?) async {
        guard let api else { return }
        do {
            _ = try await api.addVisited(countryCode: countryCode, city: city, year: year)
            await load()
        } catch {
            errorMessage = "Couldn't add that place: \(error.localizedDescription)"
        }
    }

    func delete(_ place: VisitedPlaceRecord) async {
        guard let api else { return }
        do {
            try await api.deleteVisited(id: place.id)
            visited.removeAll { $0.id == place.id }
        } catch {
            errorMessage = "Couldn't remove that place: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: ProfileRecord?
    @Published private(set) var tripCount: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isUploadingAvatar = false
    @Published var errorMessage: String?

    private var api: WandererAPI? { CloudSession.shared.api }

    func load() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await api.profile()
        } catch {
            errorMessage = "Couldn't load your profile: \(error.localizedDescription)"
        }
    }

    func update(locale: String, currency: String, units: String) async {
        guard profile != nil, let api else { return }
        do {
            self.profile = try await api.updateProfile(locale: locale, currency: currency, units: units)
        } catch {
            errorMessage = "Couldn't save your settings: \(error.localizedDescription)"
        }
    }

    /// Leaves `tripCount` nil on failure so the UI hides the stat instead of
    /// showing 0.
    func loadTripCount() async {
        guard let api else { return }
        tripCount = try? await api.trips().count
    }

    /// Returns true on success.
    @discardableResult
    func updateAvatar(imageData: Data) async -> Bool {
        guard profile != nil, let api else {
            errorMessage = "Sign in to add a profile photo."
            return false
        }
        errorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            self.profile = try await api.uploadAvatar(imageData)
            return true
        } catch {
            errorMessage = "Couldn't update your photo: \(error.localizedDescription)"
            return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
