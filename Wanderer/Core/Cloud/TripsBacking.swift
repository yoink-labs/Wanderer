import Foundation

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
            if let token = await provider() {
                return token
            }
        }
        if let token = state.token {
            return token
        }
        #if DEBUG
        // Local integration runs set WANDERER_TEST_TOKEN. The Worker only
        // accepts `test:` tokens when it is itself in test mode.
        if let debugToken = ProcessInfo.processInfo.environment["WANDERER_TEST_TOKEN"] {
            return debugToken
        }
        #endif
        return nil
    }

    #if DEBUG
    var debugToken: String? {
        ProcessInfo.processInfo.environment["WANDERER_TEST_TOKEN"]
    }
    #endif

    var api: WandererAPI? {
        guard CloudConfiguration.isAPIConfigured else { return nil }
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

/// Storage behind `TripsStore`.
protocol TripsBacking {
    func load() async throws -> [TripRecord]
    func create(_ draft: NewTripDraft) async throws -> TripRecord
    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async throws -> TripRecord
    func delete(_ trip: Trip) async throws
    func updateCover(_ trip: Trip, imageData: Data) async throws -> String?
    func updateNotes(_ trip: Trip, notes: String) async throws -> TripRecord
}

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
