import Foundation

/// An in-process stand-in for the Wanderer Worker, used for guest trips.
///
/// It speaks the same REST routes the API client sends (`/v1/trips/:id/...`)
/// and keeps each trip's rows as JSON on the device, so a guest can plan a
/// whole trip (days, places, lists, bookings, costs, checklist) offline with
/// exactly the code paths a signed-in person uses. Nothing here touches the
/// network.
struct LocalTripServer: URLSessioning {
    let store: LocalTripStore

    static let shared = LocalTripServer(store: LocalTripStore(directory: LocalTripStore.defaultDirectory))
    static let baseURL = URL(string: "https://local.wanderer.invalid")!

    /// API client wired to the local server. The token is a fixed placeholder:
    /// the local server has a single, implicit user.
    static func api(_ server: LocalTripServer = .shared) -> WandererAPI {
        WandererAPI(baseURL: baseURL, auth: APIAuth { "local" }, session: server)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = request.httpMethod ?? "GET"
        let parts = request.url?.path.split(separator: "/").map(String.init) ?? []
        var body: Any?
        if let data = request.httpBody, !data.isEmpty {
            body = try? JSONSerialization.jsonObject(with: data)
        }
        let (status, payload) = await store.handle(method: method, parts: parts, body: body)
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
        let response = HTTPURLResponse(
            url: request.url ?? Self.baseURL,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"]
        )!
        return (data, response)
    }
}

/// File-backed rows for local trips: one JSON document per trip, holding a
/// list of rows per collection.
actor LocalTripStore {
    typealias Row = [String: Any]

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("local-trips", isDirectory: true)
    }

    /// The one local person. Stable so expenses and splits keep pointing at
    /// the same member across launches.
    static let localUserID = "00000000-0000-4000-8000-00000000a11e"

    static let collections: Set<String> = [
        "days", "places", "lists", "reservations", "expenses",
        "expense-splits", "settlements", "checklist"
    ]

    private let directory: URL
    private var cache: [String: [String: [Row]]] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: Routing

    func handle(method: String, parts: [String], body: Any?) -> (Int, Any) {
        if parts == ["v1", "me"] {
            return (200, localProfile())
        }
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "trips" else {
            return notFound()
        }
        let tripID = parts[2].lowercased()

        if parts.count == 3 {
            guard method == "PATCH" else { return notFound() }
            return (200, patchTrip(tripID, body as? Row ?? [:]))
        }

        let collection = parts[3]
        if collection == "members" {
            return (200, [localMember()])
        }
        guard Self.collections.contains(collection) else { return notFound() }

        switch (method, parts.count) {
        case ("GET", 4):
            return (200, sorted(rows(tripID, collection), collection))
        case ("POST", 4):
            if let array = body as? [Row] {
                return (201, array.map { insert(tripID, collection, $0) })
            }
            return (201, insert(tripID, collection, body as? Row ?? [:]))
        case ("PATCH", 5):
            guard let row = update(tripID, collection, id: parts[4], with: body as? Row ?? [:]) else {
                return notFound()
            }
            return (200, row)
        case ("DELETE", 5):
            delete(tripID, collection, id: parts[4])
            return (200, ["ok": true])
        default:
            return notFound()
        }
    }

    // MARK: Rows

    private func rows(_ tripID: String, _ collection: String) -> [Row] {
        if collection == "days", document(tripID)["days"]?.isEmpty ?? true {
            seedDays(tripID)
        }
        return document(tripID)[collection] ?? []
    }

    private func insert(_ tripID: String, _ collection: String, _ input: Row) -> Row {
        var row = defaults(for: collection)
        for (key, value) in input where key != "splits" {
            row[key] = Self.normalized(value)
        }
        row["id"] = (input["id"] as? String)?.lowercased() ?? UUID().uuidString.lowercased()
        row["trip_id"] = tripID
        row["created_at"] = Self.now()
        var doc = document(tripID)
        doc[collection, default: []].append(row)

        // Expenses carry their splits in the same request, like the Worker.
        if collection == "expenses", let splits = input["splits"] as? [Row] {
            for split in splits {
                var splitRow: Row = ["weight": NSNull()]
                for (key, value) in split { splitRow[key] = Self.normalized(value) }
                splitRow["id"] = UUID().uuidString.lowercased()
                splitRow["trip_id"] = tripID
                splitRow["expense_id"] = row["id"]
                doc["expense-splits", default: []].append(splitRow)
            }
        }
        save(tripID, doc)
        return row
    }

    private func update(_ tripID: String, _ collection: String, id: String, with changes: Row) -> Row? {
        var doc = document(tripID)
        var list = doc[collection] ?? []
        guard let index = list.firstIndex(where: { ($0["id"] as? String)?.lowercased() == id.lowercased() }) else {
            return nil
        }
        for (key, value) in changes {
            list[index][key] = Self.normalized(value)
        }
        doc[collection] = list
        save(tripID, doc)
        return list[index]
    }

    private func delete(_ tripID: String, _ collection: String, id: String) {
        let key = id.lowercased()
        var doc = document(tripID)
        doc[collection]?.removeAll { ($0["id"] as? String)?.lowercased() == key }

        switch collection {
        case "days":
            // Deleting a day unschedules its places instead of losing them.
            doc["places"] = doc["places"]?.map { place in
                var place = place
                if (place["day_id"] as? String)?.lowercased() == key { place["day_id"] = NSNull() }
                return place
            }
        case "lists":
            doc["places"] = doc["places"]?.map { place in
                var place = place
                if (place["list_id"] as? String)?.lowercased() == key { place["list_id"] = NSNull() }
                return place
            }
        case "expenses":
            doc["expense-splits"]?.removeAll { ($0["expense_id"] as? String)?.lowercased() == key }
        default:
            break
        }
        save(tripID, doc)
    }

    private func sorted(_ rows: [Row], _ collection: String) -> [Row] {
        let key: String
        switch collection {
        case "days": key = "day_index"
        case "reservations": key = "start_at"
        case "expenses": key = "spent_at"
        default: key = "position"
        }
        return rows.sorted { lhs, rhs in
            switch (lhs[key], rhs[key]) {
            case let (a as Int, b as Int): return a < b
            case let (a as Double, b as Double): return a < b
            case let (a as String, b as String): return a < b
            case (is NSNull, _), (nil, _): return false
            default: return true
            }
        }
    }

    private func defaults(for collection: String) -> Row {
        switch collection {
        case "places":
            return ["day_id": NSNull(), "list_id": NSNull(), "category": "sight", "position": 0, "visited_at": NSNull()]
        case "lists", "checklist":
            return ["position": 0, "is_checked": false]
        case "reservations":
            return ["type": "other", "currency": "USD"]
        case "expenses":
            return [
                "currency": "USD", "category": "other", "paid_by": Self.localUserID,
                "split_with": [Self.localUserID], "split_mode": "equal",
                "spent_at": String(Self.now().prefix(10)), "notes": NSNull(), "place_id": NSNull()
            ]
        case "settlements":
            return ["currency": "USD", "settled_at": String(Self.now().prefix(10)), "note": NSNull()]
        default:
            return [:]
        }
    }

    /// Days for a trip that has none yet, from the guest trip's date range.
    private func seedDays(_ tripID: String) {
        let known: [Trip] = GuestTripsStore.load() + Trip.samples
        guard let trip = known.first(where: { $0.id.uuidString.lowercased() == tripID }) else { return }
        let start: Date? = TripDayRecord.date(from: trip.startDate)
        var days: [Row] = []
        for index in 0..<max(1, trip.days) {
            var row: Row = ["id": UUID().uuidString.lowercased(), "trip_id": tripID, "day_index": index]
            row["title"] = NSNull()
            row["notes"] = NSNull()
            if let start, let date = Calendar.current.date(byAdding: .day, value: index, to: start) {
                row["date"] = Trip.isoDay(date)
            } else {
                row["date"] = NSNull()
            }
            days.append(row)
        }
        var doc = document(tripID)
        doc["days"] = days
        save(tripID, doc)
    }

    private func patchTrip(_ tripID: String, _ changes: Row) -> Row {
        var trips = GuestTripsStore.load()
        if let index = trips.firstIndex(where: { $0.id.uuidString.lowercased() == tripID }) {
            if let end = changes["end_date"] as? String { trips[index].endDate = end }
            if let notes = changes["notes"] as? String { trips[index].notes = notes }
            GuestTripsStore.save(trips)
        }
        let trip = trips.first { $0.id.uuidString.lowercased() == tripID }
        return [
            "id": tripID,
            "owner_id": Self.localUserID,
            "title": trip?.title ?? "Trip",
            "destination": trip?.destination ?? NSNull(),
            "start_date": trip?.startDate ?? NSNull(),
            "end_date": trip?.endDate ?? NSNull(),
            "currency": "USD",
            "timezone": trip?.timezone ?? TimeZone.current.identifier
        ]
    }

    private func localProfile() -> Row {
        ["id": Self.localUserID, "email": NSNull(), "display_name": "You", "avatar_url": NSNull(),
         "locale": "en", "currency": "USD", "units": "metric"]
    }

    private func localMember() -> Row {
        ["user_id": Self.localUserID, "role": "owner",
         "profiles": ["id": Self.localUserID, "display_name": "You", "email": NSNull()]]
    }

    private func notFound() -> (Int, Any) {
        (404, ["error": ["code": "not_available_offline", "message": "Sign in to use this on a guest trip."]])
    }

    // MARK: Storage

    private func fileURL(_ tripID: String) -> URL {
        directory.appendingPathComponent("\(tripID).json")
    }

    private func document(_ tripID: String) -> [String: [Row]] {
        if let cached = cache[tripID] { return cached }
        guard let data = try? Data(contentsOf: fileURL(tripID)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [Row]] else {
            return [:]
        }
        cache[tripID] = object
        return object
    }

    private func save(_ tripID: String, _ doc: [String: [Row]]) {
        cache[tripID] = doc
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: doc)
            try data.write(to: fileURL(tripID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Rows stay in memory for this session if the disk write fails.
        }
    }

    /// Everything stored for a trip, for copying into an account on sign-in.
    func snapshot(tripID: UUID) -> [String: [Row]] {
        document(tripID.uuidString.lowercased())
    }

    func removeAll() {
        cache = [:]
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    /// UUID strings are stored lowercased so lookups never depend on casing.
    private static func normalized(_ value: Any) -> Any {
        if let string = value as? String, string.count == 36, UUID(uuidString: string) != nil {
            return string.lowercased()
        }
        if let array = value as? [Any] {
            return array.map(normalized)
        }
        return value
    }

    private static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

/// Whether trip content should be read from and written to the device.
enum LocalTrips {
    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: "wanderer.isGuest") && !CloudSession.shared.isSignedIn
    }
}
