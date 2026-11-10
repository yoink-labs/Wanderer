#if DEBUG
import Foundation

/// Creates a small, realistic trip through the same API client the app uses,
/// so simulator runs can verify sign-in → D1 → R2 without typing (the
/// simulator keyboard is not reliable under automation). Debug builds only.
enum DebugSeed {
    private static func note(_ line: String) throws {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("debug-seed.log") else { return }
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (existing + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func runIfRequested() async {
        guard ProcessInfo.processInfo.environment["WANDERER_TEST_SEED"] != nil else { return }
        let key = "wanderer.debugSeedTripID.v3"
        guard UserDefaults.standard.string(forKey: key) == nil else { return }
        guard let api = CloudSession.shared.api else { return }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: 12, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .day, value: 16, to: start) ?? start
        let draft = NewTripDraft(
            title: "Yoink Test Trip",
            destination: "Lisbon, Portugal",
            startDate: start,
            endDate: end,
            days: 5,
            dateRange: "Test dates",
            coverColor: "#D77A61",
            timezone: "Europe/Lisbon"
        )

        do {
            try note("start")
            let trip = try await api.createTrip(draft)
            try note("trip \(trip.id)")
            UserDefaults.standard.set(trip.id.uuidString, forKey: key)

            let days = try await api.days(tripID: trip.id)
            try note("days \(days.count)")
            let stops: [(String, Double, Double, String)] = [
                ("Time Out Market", 38.7071, -9.1459, "food"),
                ("Castelo de São Jorge", 38.7139, -9.1335, "sight")
            ]
            for (index, stop) in stops.enumerated() {
                _ = try await api.addPlace(tripID: trip.id, body: [
                    "name": .string(stop.0),
                    "day_id": .optional(days.first?.id),
                    "lat": .number(stop.1),
                    "lng": .number(stop.2),
                    "category": .string(stop.3),
                    "position": .integer(index)
                ])
            }

            try note("places done")
            let receipt = Data("Wanderer end-to-end receipt\n\(Date())\n".utf8)
            _ = try await api.uploadAttachment(
                tripID: trip.id,
                data: receipt,
                fileName: "e2e-receipt.txt",
                mimeType: "text/plain"
            )

            try note("attachment done")
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        } catch {
            // Keep a non-sensitive reason for local diagnosis; never a token.
            try? note("failed: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
#endif
