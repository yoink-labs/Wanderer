import Foundation
import Supabase

/// Holds the current Clerk session token for the API client.
///
/// A tiny lock-protected box rather than an observable object so non-main
/// actors (the API client, uploads) can read the token without hopping to the
/// main actor. The auth store is the only writer.
final class CloudSession: @unchecked Sendable {
    static let shared = CloudSession()

    private let lock = NSLock()
    private var tokenValue: String?
    private var tokenProvider: (@Sendable () async -> String?)?

    var token: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return tokenValue
        }
        set {
            lock.lock()
            tokenValue = newValue
            lock.unlock()
        }
    }

    var isSignedIn: Bool { token != nil }

    /// Set by the auth store so the client can refresh an expiring token
    /// before a request instead of failing with a 401.
    func setProvider(_ provider: @escaping @Sendable () async -> String?) {
        lock.lock()
        tokenProvider = provider
        lock.unlock()
    }

    private func snapshot() -> (provider: (@Sendable () async -> String?)?, token: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (tokenProvider, tokenValue)
    }

    func currentToken() async -> String? {
        let state = snapshot()
        if let provider = state.provider {
            return await provider()
        }
        return state.token
    }

    var api: WandererAPI? {
        guard BackendMode.isCloudAvailable else { return nil }
        return WandererAPI.live(auth: APIAuth { [weak self] in
            await self?.currentToken()
        })
    }
}

extension NewTripDraft {
    /// Request body for `POST /v1/trips`. The API creates the day rows from the
    /// date range, so there is no second write to lose.
    var apiBody: [String: JSONValue] {
        [
            "title": .string(title),
            "destination": .string(destination),
            "start_date": .string(Self.apiDate(startDate)),
            "end_date": .string(Self.apiDate(endDate)),
            "cover_color": .string(coverColor),
            "timezone": .string(timezone)
        ]
    }

    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Storage behind `TripsStore`, so the same screens can read Supabase today
/// and the Worker after cutover.
protocol TripsBacking {
    func load() async throws -> [TripRecord]
    func create(_ draft: NewTripDraft) async throws -> TripRecord
    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async throws -> TripRecord
    func delete(_ trip: Trip) async throws
    func updateCover(_ trip: Trip, imageData: Data) async throws -> String?
    func updateNotes(_ trip: Trip, notes: String) async throws -> TripRecord
}

// MARK: - Supabase

/// The existing Supabase path, unchanged in behaviour. Kept until the Worker
/// cutover is verified, and removable in one commit afterwards.
struct SupabaseTripsBacking: TripsBacking {
    private let client = WandererSupabase.client

    func load() async throws -> [TripRecord] {
        guard client.auth.currentSession != nil else { return [] }
        var records: [TripRecord] = try await client
            .from("trips")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        let placeRows: [TripPlaceRow] = try await client
            .from("places")
            .select("trip_id")
            .execute()
            .value
        let counts = Dictionary(grouping: placeRows, by: \.tripId).mapValues(\.count)
        for index in records.indices {
            records[index].placeCount = counts[records[index].id] ?? 0
        }
        return records
    }

    func create(_ draft: NewTripDraft) async throws -> TripRecord {
        let session = try await client.auth.session
        let payload = NewTripPayload(
            ownerId: session.user.id,
            title: draft.title,
            destination: draft.destination,
            startDate: NewTripDraft.apiDate(draft.startDate),
            endDate: NewTripDraft.apiDate(draft.endDate),
            coverColor: draft.coverColor,
            timezone: draft.timezone
        )
        let record: TripRecord = try await client
            .from("trips")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        try await createDays(for: record.id, start: draft.startDate, days: draft.days)
        return record
    }

    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async throws -> TripRecord {
        let days = max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
        let payload = TripUpdatePayload(
            title: title,
            destination: destination,
            startDate: NewTripDraft.apiDate(startDate),
            endDate: NewTripDraft.apiDate(endDate)
        )
        let updated: TripRecord = try await client.from("trips")
            .update(payload)
            .eq("id", value: trip.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        try await syncDays(for: trip.id, start: startDate, days: days)
        return updated
    }

    func delete(_ trip: Trip) async throws {
        try await client.from("trips")
            .delete()
            .eq("id", value: trip.id.uuidString)
            .execute()
    }

    func updateCover(_ trip: Trip, imageData: Data) async throws -> String? {
        let session = try await client.auth.session
        let path = "\(session.user.id.uuidString.lowercased())/\(trip.id.uuidString.lowercased())-cover-\(Int(Date().timeIntervalSince1970)).jpg"
        try await client.storage
            .from("trip-covers")
            .upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        let publicURL = try client.storage.from("trip-covers").getPublicURL(path: path)
        let updated: TripRecord = try await client.from("trips")
            .update(["cover_url": publicURL.absoluteString])
            .eq("id", value: trip.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return updated.coverUrl
    }

    func updateNotes(_ trip: Trip, notes: String) async throws -> TripRecord {
        try await client.from("trips")
            .update(["notes": notes])
            .eq("id", value: trip.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    private func createDays(for tripID: UUID, start: Date, days: Int) async throws {
        guard days > 0 else { return }
        let calendar = Calendar.current
        let payloads = (0..<days).map { offset in
            NewDayPayload(
                tripId: tripID,
                dayIndex: offset,
                date: NewTripDraft.apiDate(calendar.date(byAdding: .day, value: offset, to: start) ?? start),
                title: nil
            )
        }
        try await client.from("trip_days").insert(payloads).execute()
    }

    private func syncDays(for tripID: UUID, start: Date, days: Int) async throws {
        let existing: [TripDayRecord] = try await client.from("trip_days")
            .select()
            .eq("trip_id", value: tripID.uuidString)
            .order("day_index", ascending: true)
            .execute()
            .value

        let calendar = Calendar.current
        for index in 0..<days {
            let date = NewTripDraft.apiDate(calendar.date(byAdding: .day, value: index, to: start) ?? start)
            if let day = existing.first(where: { $0.dayIndex == index }) {
                try await client.from("trip_days")
                    .update(["date": date])
                    .eq("id", value: day.id.uuidString)
                    .execute()
            } else {
                let payload = NewDayPayload(tripId: tripID, dayIndex: index, date: date, title: nil)
                try await client.from("trip_days").insert(payload).execute()
            }
        }
        for day in existing where day.dayIndex >= days {
            try await client.from("trip_days").delete().eq("id", value: day.id.uuidString).execute()
        }
    }
}

// MARK: - Cloud

struct CloudTripsBacking: TripsBacking {
    private var api: WandererAPI {
        get throws {
            guard let api = CloudSession.shared.api else {
                throw APIError(
                    status: 503,
                    code: "api_not_configured",
                    message: "The Wanderer server is not configured for this build."
                )
            }
            return api
        }
    }

    func load() async throws -> [TripRecord] {
        try await api.trips()
    }

    func create(_ draft: NewTripDraft) async throws -> TripRecord {
        try await api.createTrip(draft)
    }

    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async throws -> TripRecord {
        try await api.updateTrip(
            id: trip.id,
            title: title,
            destination: destination,
            startDate: NewTripDraft.apiDate(startDate),
            endDate: NewTripDraft.apiDate(endDate)
        )
    }

    func delete(_ trip: Trip) async throws {
        try await api.deleteTrip(id: trip.id)
    }

    func updateCover(_ trip: Trip, imageData: Data) async throws -> String? {
        try await api.uploadTripCover(id: trip.id, data: imageData).coverUrl
    }

    func updateNotes(_ trip: Trip, notes: String) async throws -> TripRecord {
        try await api.updateTripNotes(id: trip.id, notes: notes)
    }
}

// MARK: - Payloads

private struct TripPlaceRow: Decodable {
    let tripId: UUID

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
    }
}

private struct NewTripPayload: Encodable {
    let ownerId: UUID
    let title: String
    let destination: String
    let startDate: String
    let endDate: String
    let coverColor: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case title
        case destination
        case startDate = "start_date"
        case endDate = "end_date"
        case coverColor = "cover_color"
        case timezone
    }
}

private struct TripUpdatePayload: Encodable {
    let title: String
    let destination: String
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case title, destination
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

private struct NewDayPayload: Encodable {
    let tripId: UUID
    let dayIndex: Int
    let date: String
    let title: String?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case dayIndex = "day_index"
        case date
        case title
    }
}
