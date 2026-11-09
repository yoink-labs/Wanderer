import Foundation
import Supabase

@MainActor
final class TripsStore: ObservableObject {
    @Published private(set) var trips: [TripRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

    func load() async {
        guard WandererSupabase.client.auth.currentSession != nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
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
            trips = records
        } catch {
            errorMessage = "Couldn't load your trips: \(error.localizedDescription)"
        }
    }

    func create(_ draft: NewTripDraft) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await client.auth.session
            let payload = NewTripPayload(
                ownerId: session.user.id,
                title: draft.title,
                destination: draft.destination,
                startDate: Self.dateString(draft.startDate),
                endDate: Self.dateString(draft.endDate),
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
            trips.insert(record, at: 0)
        } catch {
            errorMessage = "Couldn't create the trip: \(error.localizedDescription)"
        }
    }

    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let days = max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)

        do {
            let payload = TripUpdatePayload(
                title: title,
                destination: destination,
                startDate: Self.dateString(startDate),
                endDate: Self.dateString(endDate)
            )
            let updated: TripRecord = try await client.from("trips")
                .update(payload)
                .eq("id", value: trip.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            try await syncDays(for: trip.id, start: startDate, days: days)
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updated
            }
        } catch {
            errorMessage = "Couldn't save the trip: \(error.localizedDescription)"
        }
    }

    func updateCover(_ trip: Trip, imageData: Data) async -> String? {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
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

            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updated
            }
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
            return publicURL.absoluteString
        } catch {
            errorMessage = "Couldn't update the cover: \(error.localizedDescription)"
            return nil
        }
    }

    func updateNotes(_ trip: Trip, notes: String) async {
        errorMessage = nil
        do {
            let updated: TripRecord = try await client.from("trips")
                .update(["notes": notes])
                .eq("id", value: trip.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updated
            }
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        } catch {
            errorMessage = "Couldn't save the notes: \(error.localizedDescription)"
        }
    }

    func delete(_ trip: Trip) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.from("trips")
                .delete()
                .eq("id", value: trip.id.uuidString)
                .execute()
            trips.removeAll { $0.id == trip.id }
        } catch {
            errorMessage = "Couldn't delete the trip: \(error.localizedDescription)"
        }
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
            let date = Self.dateString(calendar.date(byAdding: .day, value: index, to: start) ?? start)
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

    private func createDays(for tripID: UUID, start: Date, days: Int) async throws {
        guard days > 0 else { return }
        let calendar = Calendar.current
        let payloads = (0..<days).map { offset in
            NewDayPayload(
                tripId: tripID,
                dayIndex: offset,
                date: Self.dateString(calendar.date(byAdding: .day, value: offset, to: start) ?? start),
                title: nil
            )
        }
        try await client.from("trip_days").insert(payloads).execute()
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct NewTripDraft {
    let title: String
    let destination: String
    let startDate: Date
    let endDate: Date
    let days: Int
    let dateRange: String
    let coverColor: String
    let timezone: String

    func asLocalTrip(memberInitials: [String]) -> Trip {
        Trip(
            title: title,
            destination: destination,
            dateRange: dateRange,
            days: days,
            places: 0,
            members: memberInitials,
            palette: TripPalette.allCases.randomElement() ?? .lagoon,
            symbol: "airplane",
            timezone: timezone
        )
    }
}

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
