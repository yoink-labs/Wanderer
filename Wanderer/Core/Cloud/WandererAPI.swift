import Foundation

/// Minimal JSON value used for request bodies, so callers can post partial
/// rows without declaring a struct for every endpoint.
enum JSONValue: Encodable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }

    static func optional(_ value: String?) -> JSONValue {
        value.map { .string($0) } ?? .null
    }

    static func optional(_ value: Double?) -> JSONValue {
        value.map { .number($0) } ?? .null
    }

    static func optional(_ value: Int?) -> JSONValue {
        value.map { .integer($0) } ?? .null
    }

    static func optional(_ value: UUID?) -> JSONValue {
        value.map { .string($0.uuidString) } ?? .null
    }
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }

    let error: Detail
}

/// A failure from the Wanderer API. `code` is stable enough for the UI to
/// branch on (`not_authenticated`, `read_only`, `rate_limited`, ...).
struct APIError: LocalizedError, Equatable {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? { message }

    var isAuthenticationFailure: Bool {
        status == 401 || code == "not_authenticated" || code == "expired_token"
    }

    var isOffline: Bool { code == "offline" }
}

protocol URLSessioning: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessioning {}

/// Typed client for the Wanderer Worker API.
///
/// Every call carries the Clerk session JWT. Rows are decoded into the same
/// models the Supabase stores already use, so migrating a store is a call-site
/// change rather than a model change.
struct WandererAPI: Sendable {
    let baseURL: URL
    let auth: APIAuth
    let session: URLSessioning
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        auth: APIAuth,
        session: URLSessioning = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.auth = auth
        self.session = session
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    static func live(auth: APIAuth) -> WandererAPI? {
        guard let url = CloudConfiguration.apiURL else { return nil }
        return WandererAPI(baseURL: url, auth: auth)
    }

    // MARK: - Health / identity

    func health() async throws -> Bool {
        struct Health: Decodable { let ok: Bool }
        let response: Health = try await send("GET", "/health", authenticated: false)
        return response.ok
    }

    func profile() async throws -> ProfileRecord {
        try await send("GET", "/v1/me")
    }

    func updateProfile(locale: String, currency: String, units: String) async throws -> ProfileRecord {
        try await send("PATCH", "/v1/me", body: [
            "locale": .string(locale),
            "currency": .string(currency),
            "units": .string(units)
        ])
    }

    func uploadAvatar(_ data: Data, contentType: String = "image/jpeg") async throws -> ProfileRecord {
        try await upload("/v1/me/avatar", data: data, contentType: contentType)
    }

    // MARK: - Trips

    func trips() async throws -> [TripRecord] {
        try await send("GET", "/v1/trips")
    }

    func trip(id: UUID) async throws -> TripRecord {
        try await send("GET", "/v1/trips/\(id.uuidString)")
    }

    func createTrip(_ draft: NewTripDraft) async throws -> TripRecord {
        try await send("POST", "/v1/trips", body: draft.apiBody, idempotent: true)
    }

    func updateTrip(
        id: UUID,
        title: String,
        destination: String,
        startDate: String?,
        endDate: String?
    ) async throws -> TripRecord {
        try await send("PATCH", "/v1/trips/\(id.uuidString)", body: [
            "title": .string(title),
            "destination": .string(destination),
            "start_date": .optional(startDate),
            "end_date": .optional(endDate)
        ])
    }

    func deleteTrip(id: UUID) async throws {
        try await sendEmpty("DELETE", "/v1/trips/\(id.uuidString)")
    }

    func updateTripNotes(id: UUID, notes: String) async throws -> TripRecord {
        try await send("PATCH", "/v1/trips/\(id.uuidString)", body: ["notes": .string(notes)])
    }

    func uploadTripCover(id: UUID, data: Data, contentType: String = "image/jpeg") async throws -> TripRecord {
        try await upload("/v1/trips/\(id.uuidString)/cover", data: data, contentType: contentType)
    }

    // MARK: - Trip content

    func days(tripID: UUID) async throws -> [TripDayRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/days")
    }

    func updateDay(tripID: UUID, dayID: UUID, notes: String?) async throws -> TripDayRecord {
        try await send("PATCH", "/v1/trips/\(tripID.uuidString)/days/\(dayID.uuidString)", body: [
            "notes": .optional(notes)
        ])
    }

    func places(tripID: UUID) async throws -> [PlaceRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/places")
    }

    func addPlace(tripID: UUID, body: [String: JSONValue]) async throws -> PlaceRecord {
        try await send("POST", "/v1/trips/\(tripID.uuidString)/places", body: body)
    }

    func updatePlace(tripID: UUID, placeID: UUID, body: [String: JSONValue]) async throws -> PlaceRecord {
        try await send("PATCH", "/v1/trips/\(tripID.uuidString)/places/\(placeID.uuidString)", body: body)
    }

    func deletePlace(tripID: UUID, placeID: UUID) async throws {
        try await sendEmpty("DELETE", "/v1/trips/\(tripID.uuidString)/places/\(placeID.uuidString)")
    }

    func reservations(tripID: UUID) async throws -> [ReservationRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/reservations")
    }

    func expenses(tripID: UUID) async throws -> [ExpenseRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/expenses")
    }

    func expenseSplits(tripID: UUID) async throws -> [ExpenseSplitRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/expense-splits")
    }

    func settlements(tripID: UUID) async throws -> [SettlementRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/settlements")
    }

    func checklist(tripID: UUID) async throws -> [ChecklistRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/checklist")
    }

    func members(tripID: UUID) async throws -> [TripMemberProfile] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/members")
    }

    func invites(tripID: UUID) async throws -> [TripInviteRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/invites")
    }

    // MARK: - Files

    func attachments(tripID: UUID) async throws -> [AttachmentRecord] {
        try await send("GET", "/v1/trips/\(tripID.uuidString)/attachments")
    }

    func uploadAttachment(
        tripID: UUID,
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> AttachmentRecord {
        try await upload(
            "/v1/trips/\(tripID.uuidString)/attachments",
            data: data,
            contentType: mimeType,
            extraHeaders: ["x-file-name": fileName]
        )
    }

    func attachmentURL(tripID: UUID, attachmentID: UUID) async throws -> URL {
        struct Payload: Decodable { let url: String }
        let payload: Payload = try await send(
            "GET",
            "/v1/trips/\(tripID.uuidString)/attachments/\(attachmentID.uuidString)/url"
        )
        guard let url = URL(string: payload.url, relativeTo: baseURL) else {
            throw APIError(status: 500, code: "bad_url", message: "The server returned an invalid file link.")
        }
        return url
    }

    func deleteAttachment(tripID: UUID, attachmentID: UUID) async throws {
        try await sendEmpty("DELETE", "/v1/trips/\(tripID.uuidString)/attachments/\(attachmentID.uuidString)")
    }

    // MARK: - Guides / visited

    func guides(query: String? = nil) async throws -> [GuideRecord] {
        let items = query.map { [URLQueryItem(name: "q", value: $0)] } ?? []
        return try await send("GET", "/v1/guides", query: items, authenticated: false)
    }

    func guidePlaces(guideID: UUID) async throws -> [GuidePlaceRecord] {
        try await send("GET", "/v1/guides/\(guideID.uuidString)/places", authenticated: false)
    }

    func visitedPlaces() async throws -> [VisitedPlaceRecord] {
        try await send("GET", "/v1/visited")
    }

    func addVisited(countryCode: String, city: String?, year: Int?) async throws -> VisitedPlaceRecord {
        try await send("POST", "/v1/visited", body: [
            "country_code": .string(countryCode),
            "city": .optional(city),
            "year": .optional(year)
        ])
    }

    func deleteVisited(id: UUID) async throws {
        try await sendEmpty("DELETE", "/v1/visited/\(id.uuidString)")
    }

    // MARK: - Transport

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil,
        authenticated: Bool = true,
        idempotent: Bool = false
    ) async throws -> T {
        let data = try await perform(
            method,
            path,
            query: query,
            body: body,
            authenticated: authenticated,
            idempotent: idempotent
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(
                status: 500,
                code: "decode_failed",
                message: "The server sent a response Wanderer could not read."
            )
        }
    }

    private func sendEmpty(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws {
        _ = try await perform(
            method,
            path,
            query: query,
            body: nil,
            authenticated: true,
            idempotent: false
        )
    }

    private func upload<T: Decodable>(
        _ path: String,
        data: Data,
        contentType: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        var request = try await makeRequest(
            method: "POST",
            path: path,
            query: [],
            authenticated: true,
            idempotent: true
        )
        request.setValue(contentType, forHTTPHeaderField: "content-type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = data
        let (responseData, response) = try await execute(request)
        try validate(response, data: responseData)
        do {
            return try decoder.decode(T.self, from: responseData)
        } catch {
            throw APIError(
                status: 500,
                code: "decode_failed",
                message: "The server sent a response Wanderer could not read."
            )
        }
    }

    private func perform(
        _ method: String,
        _ path: String,
        query: [URLQueryItem],
        body: [String: JSONValue]?,
        authenticated: Bool,
        idempotent: Bool
    ) async throws -> Data {
        var request = try await makeRequest(
            method: method,
            path: path,
            query: query,
            authenticated: authenticated,
            idempotent: idempotent
        )
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await execute(request)
        try validate(response, data: data)
        return data
    }

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem],
        authenticated: Bool,
        idempotent: Bool
    ) async throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError(status: 500, code: "bad_url", message: "The API URL is invalid.")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError(status: 500, code: "bad_url", message: "The API URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Wanderer/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")", forHTTPHeaderField: "user-agent")
        if idempotent {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "idempotency-key")
        }
        if authenticated {
            guard let token = await auth.token(), !token.isEmpty else {
                throw APIError(status: 401, code: "not_authenticated", message: "Sign in to continue.")
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        return request
    }

    private func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            let offline = error.code == .notConnectedToInternet
                || error.code == .networkConnectionLost
                || error.code == .timedOut
                || error.code == .cannotConnectToHost
            throw APIError(
                status: 0,
                code: offline ? "offline" : "network_error",
                message: offline
                    ? "You're offline. Wanderer will try again when the connection is back."
                    : "The server could not be reached."
            )
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? decoder.decode(APIErrorBody.self, from: data) {
                throw APIError(status: http.statusCode, code: body.error.code, message: body.error.message)
            }
            throw APIError(
                status: http.statusCode,
                code: "http_\(http.statusCode)",
                message: "The server rejected that request."
            )
        }
    }
}
