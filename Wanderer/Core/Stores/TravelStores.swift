import Foundation
import Supabase

@MainActor
final class ExploreStore: ObservableObject {
    @Published private(set) var guides: [GuideRecord] = []
    @Published private(set) var placesByGuide: [UUID: [GuidePlaceRecord]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

    private var cloud: WandererAPI? {
        BackendMode.current == .cloud ? CloudSession.shared.api : nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let cloud {
            do {
                guides = try await cloud.guides()
            } catch {
                errorMessage = "Couldn't load guides: \(error.localizedDescription)"
            }
            return
        }

        do {
            guides = try await client.from("guides")
                .select()
                .eq("is_published", value: true)
                .order("title", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't load guides: \(error.localizedDescription)"
        }
    }

    func loadPlaces(for guideID: UUID) async {
        guard placesByGuide[guideID] == nil else { return }

        if let cloud {
            do {
                placesByGuide[guideID] = try await cloud.guidePlaces(guideID: guideID)
            } catch {
                errorMessage = "Couldn't load this guide: \(error.localizedDescription)"
            }
            return
        }

        do {
            let places: [GuidePlaceRecord] = try await client.from("guide_places")
                .select()
                .eq("guide_id", value: guideID.uuidString)
                .order("position", ascending: true)
                .execute()
                .value
            placesByGuide[guideID] = places
        } catch {
            errorMessage = "Couldn't load this guide: \(error.localizedDescription)"
        }
    }

    /// Copies a guide's stops into an existing trip as unscheduled places, in
    /// guide order. The caller creates the trip (via `TripsStore.create`) first;
    /// this only writes `places` rows, which RLS allows for trip editors.
    func copyPlaces(_ places: [GuidePlaceRecord], intoTrip tripID: UUID) async throws {
        guard !places.isEmpty else { return }

        if let cloud {
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
            _ = try await cloud.addPlaces(tripID: tripID, rows: rows)
            return
        }

        let session = try await client.auth.session
        let payloads = places
            .sorted { $0.position < $1.position }
            .enumerated()
            .map { offset, place in
                GuidePlaceCopyPayload(
                    tripId: tripID.uuidString,
                    name: place.name,
                    address: place.address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    lat: place.lat,
                    lng: place.lng,
                    notes: place.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    photoUrl: place.photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    position: offset,
                    createdBy: session.user.id.uuidString
                )
            }
        try await client.from("places").insert(payloads).execute()
    }
}

@MainActor
final class VisitedStore: ObservableObject {
    @Published private(set) var visited: [VisitedPlaceRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

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

    private var cloud: WandererAPI? {
        BackendMode.current == .cloud ? CloudSession.shared.api : nil
    }

    func load() async {
        if let cloud {
            isLoading = true
            defer { isLoading = false }
            do {
                visited = try await cloud.visitedPlaces()
            } catch {
                errorMessage = "Couldn't load visited places: \(error.localizedDescription)"
            }
            return
        }

        guard WandererSupabase.client.auth.currentSession != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            visited = try await client.from("visited_places")
                .select()
                .order("country_code", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't load visited places: \(error.localizedDescription)"
        }
    }

    func add(countryCode: String, city: String?, year: Int?) async {
        if let cloud {
            do {
                _ = try await cloud.addVisited(countryCode: countryCode, city: city, year: year)
                await load()
            } catch {
                errorMessage = "Couldn't add that place: \(error.localizedDescription)"
            }
            return
        }

        do {
            let session = try await client.auth.session
            let payload = NewVisitedPayload(
                userId: session.user.id.uuidString,
                countryCode: countryCode.uppercased(),
                city: city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                year: year
            )
            try await client.from("visited_places").insert(payload).execute()
            await load()
        } catch {
            errorMessage = "Couldn't add that place: \(error.localizedDescription)"
        }
    }

    func delete(_ place: VisitedPlaceRecord) async {
        if let cloud {
            do {
                try await cloud.deleteVisited(id: place.id)
                visited.removeAll { $0.id == place.id }
            } catch {
                errorMessage = "Couldn't remove that place: \(error.localizedDescription)"
            }
            return
        }

        do {
            try await client.from("visited_places").delete().eq("id", value: place.id.uuidString).execute()
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

    private let client: SupabaseClient

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

    private var cloud: WandererAPI? {
        BackendMode.current == .cloud ? CloudSession.shared.api : nil
    }

    func load() async {
        if let cloud {
            isLoading = true
            defer { isLoading = false }
            do {
                profile = try await cloud.profile()
            } catch {
                errorMessage = "Couldn't load your profile: \(error.localizedDescription)"
            }
            return
        }

        guard WandererSupabase.client.auth.currentSession != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await client.auth.session
            let rows: [ProfileRecord] = try await client.from("profiles")
                .select()
                .eq("id", value: session.user.id.uuidString)
                .limit(1)
                .execute()
                .value
            profile = rows.first
        } catch {
            errorMessage = "Couldn't load your profile: \(error.localizedDescription)"
        }
    }

    func update(locale: String, currency: String, units: String) async {
        guard let profile else { return }

        if let cloud {
            do {
                self.profile = try await cloud.updateProfile(locale: locale, currency: currency, units: units)
            } catch {
                errorMessage = "Couldn't save your settings: \(error.localizedDescription)"
            }
            return
        }

        do {
            let payload = ProfileUpdatePayload(locale: locale, currency: currency, units: units)
            let updated: ProfileRecord = try await client.from("profiles")
                .update(payload)
                .eq("id", value: profile.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            self.profile = updated
        } catch {
            errorMessage = "Couldn't save your settings: \(error.localizedDescription)"
        }
    }

    /// Head-only count of trips the user can see (owned or shared). Leaves
    /// `tripCount` nil on failure so the UI can hide the stat instead of showing 0.
    func loadTripCount() async {
        if let cloud {
            tripCount = try? await cloud.trips().count
            return
        }

        guard client.auth.currentSession != nil else { return }
        do {
            let response = try await client.from("trips")
                .select("id", head: true, count: .exact)
                .execute()
            tripCount = response.count
        } catch {
            tripCount = nil
        }
    }

    /// Uploads JPEG data to `avatars/<uid>/avatar-<timestamp>.jpg` and stores the
    /// public URL on the profile. Returns true on success.
    @discardableResult
    func updateAvatar(imageData: Data) async -> Bool {
        guard let profile else {
            errorMessage = "Sign in to add a profile photo."
            return false
        }
        errorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        if let cloud {
            do {
                self.profile = try await cloud.uploadAvatar(imageData)
                return true
            } catch {
                errorMessage = "Couldn't update your photo: \(error.localizedDescription)"
                return false
            }
        }

        do {
            let session = try await client.auth.session
            let path = "\(session.user.id.uuidString.lowercased())/avatar-\(Int(Date().timeIntervalSince1970)).jpg"

            try await client.storage
                .from("avatars")
                .upload(
                    path,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
            let updated: ProfileRecord = try await client.from("profiles")
                .update(["avatar_url": publicURL.absoluteString])
                .eq("id", value: profile.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            self.profile = updated
            return true
        } catch {
            errorMessage = "Couldn't update your photo: \(error.localizedDescription)"
            return false
        }
    }
}

private struct NewVisitedPayload: Encodable {
    let userId: String
    let countryCode: String
    let city: String?
    let year: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case countryCode = "country_code"
        case city
        case year
    }
}

private struct GuidePlaceCopyPayload: Encodable {
    let tripId: String
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let notes: String?
    let photoUrl: String?
    let position: Int
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case name, address, lat, lng, notes, position
        case photoUrl = "photo_url"
        case createdBy = "created_by"
    }

    // PostgREST bulk inserts reject rows whose keys differ, so write nulls
    // explicitly instead of letting synthesized encoding drop nil fields.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tripId, forKey: .tripId)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encode(notes, forKey: .notes)
        try container.encode(photoUrl, forKey: .photoUrl)
        try container.encode(position, forKey: .position)
        try container.encode(createdBy, forKey: .createdBy)
    }
}

private struct ProfileUpdatePayload: Encodable {
    let locale: String
    let currency: String
    let units: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
