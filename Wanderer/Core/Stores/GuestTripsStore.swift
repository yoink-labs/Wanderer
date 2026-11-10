import Foundation

/// Guest trips are real trips kept on this device until the person signs in.
/// They are stored as JSON in Application Support so they survive relaunch,
/// then copied into the account once signed in.
enum GuestTripsStore {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("guest-trips.json")
    }

    static func load() -> [Trip] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Trip].self, from: data)) ?? []
    }

    static func save(_ trips: [Trip]) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(trips)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A failed write only means the trip stays in memory this session.
        }
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Trip {
    /// A draft the account backend can create from a guest trip.
    var guestDraft: NewTripDraft {
        let start = TripDayRecord.date(from: startDate) ?? Date()
        let end = TripDayRecord.date(from: endDate)
            ?? Calendar.current.date(byAdding: .day, value: max(1, days) - 1, to: start)
            ?? start
        let count = max(1, (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        return NewTripDraft(
            title: title,
            destination: destination,
            startDate: start,
            endDate: end,
            days: count,
            dateRange: dateRange,
            coverColor: "#D77A61",
            timezone: timezone
        )
    }
}
