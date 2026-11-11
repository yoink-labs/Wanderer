import Foundation

/// Trip-level edits for guests: title, dates, notes, cover and delete, saved
/// to the trips on this phone. Days are kept in step with the dates through
/// the on-device server, so the planner matches the new range.
struct GuestTripsBacking: TripsBacking {
    var server: WandererAPI = LocalTripServer.api()
    var coversDirectory: URL = LocalTripStore.defaultDirectory.appendingPathComponent("covers", isDirectory: true)

    /// Saved guest trips, or the first-run samples until anything is saved.
    private func current() -> [Trip] {
        let saved = GuestTripsStore.load()
        return saved.isEmpty ? Trip.samples : saved
    }

    func load() async throws -> [TripRecord] {
        current().map(TripRecord.init(guest:))
    }

    func create(_ draft: NewTripDraft) async throws -> TripRecord {
        var trips = current()
        let trip = draft.asLocalTrip(memberInitials: ["ME"])
        trips.insert(trip, at: 0)
        GuestTripsStore.save(trips)
        return TripRecord(guest: trip)
    }

    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async throws -> TripRecord {
        var trips = current()
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { throw Self.missing }
        let days = max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
        trips[index].title = title
        trips[index].destination = destination
        trips[index].startDate = Trip.isoDay(startDate)
        trips[index].endDate = Trip.isoDay(endDate)
        trips[index].days = days
        trips[index].dateRange = Trip.rangeLabel(startDate, endDate)
        GuestTripsStore.save(trips)
        try await syncDays(tripID: trip.id, start: startDate, count: days)
        return TripRecord(guest: trips[index])
    }

    func delete(_ trip: Trip) async throws {
        var trips = current()
        trips.removeAll { $0.id == trip.id }
        GuestTripsStore.save(trips)
    }

    func updateCover(_ trip: Trip, imageData: Data) async throws -> String? {
        var trips = current()
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { throw Self.missing }
        try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        // A new name each time so image caches don't show the old cover.
        let url = coversDirectory.appendingPathComponent("\(trip.id.uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).jpg")
        try imageData.write(to: url, options: .atomic)
        trips[index].coverUrl = url.absoluteString
        GuestTripsStore.save(trips)
        return url.absoluteString
    }

    func updateNotes(_ trip: Trip, notes: String) async throws -> TripRecord {
        var trips = current()
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { throw Self.missing }
        trips[index].notes = notes
        GuestTripsStore.save(trips)
        return TripRecord(guest: trips[index])
    }

    /// Makes the trip's day rows match `count` days from `start`: existing
    /// days get new dates, missing ones are added, extra ones are removed
    /// (their stops move to Ideas, never deleted).
    func syncDays(tripID: UUID, start: Date, count: Int) async throws {
        let existing = try await server.days(tripID: tripID).sorted { $0.dayIndex < $1.dayIndex }
        for index in 0..<count {
            let date = Trip.isoDay(Calendar.current.date(byAdding: .day, value: index, to: start) ?? start)
            if let day = existing.first(where: { $0.dayIndex == index }) {
                if day.date != date {
                    _ = try await server.updateDay(tripID: tripID, dayID: day.id, body: ["date": .string(date)])
                }
            } else {
                _ = try await server.addDay(tripID: tripID, index: index, date: date)
            }
        }
        for day in existing where day.dayIndex >= count {
            try await server.deleteDay(tripID: tripID, dayID: day.id)
        }
    }

    private static let missing = APIError(status: 404, code: "trip_not_found", message: "That trip isn't on this phone any more.")
}

extension TripRecord {
    /// A record for a trip kept on this phone.
    init(guest trip: Trip) {
        let json: [String: Any] = [
            "id": trip.id.uuidString,
            "owner_id": LocalTripStore.localUserID,
            "title": trip.title,
            "destination": trip.destination,
            "start_date": trip.startDate ?? NSNull(),
            "end_date": trip.endDate ?? NSNull(),
            "currency": "USD",
            "cover_url": trip.coverUrl ?? NSNull(),
            "notes": trip.notes ?? NSNull(),
            "timezone": trip.timezone,
            "place_count": trip.places
        ]
        // Decoding through the same path as server rows keeps one source of truth.
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        self = (try? JSONDecoder().decode(TripRecord.self, from: data))
            ?? (try! JSONDecoder().decode(TripRecord.self, from: Data(#"{"id":"\#(trip.id.uuidString)","owner_id":"\#(LocalTripStore.localUserID)","title":"Trip"}"#.utf8)))
    }
}
