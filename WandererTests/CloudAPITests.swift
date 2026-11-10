import XCTest
@testable import Wanderer

/// Serves canned responses so the API client can be tested without a server.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLSession turns `httpBody` into a stream by the time a URLProtocol sees
    /// it, so tests read whichever form is present.
    var capturedBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class CloudAPITests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.requests = []
        StubURLProtocol.handler = nil
    }

    private func api(token: String? = "jwt-token") -> WandererAPI {
        WandererAPI(
            baseURL: URL(string: "https://api.wanderer.test")!,
            auth: APIAuth { token },
            session: session
        )
    }

    private func respond(_ status: Int, _ json: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["content-type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    func testTripsRequestCarriesBearerTokenAndDecodesPlaceCount() async throws {
        respond(200, """
        [{
          "id": "11111111-1111-4111-8111-111111111111",
          "owner_id": "22222222-2222-4222-8222-222222222222",
          "title": "Lisbon",
          "destination": "Lisbon, Portugal",
          "start_date": "2026-11-12",
          "end_date": "2026-11-16",
          "currency": "EUR",
          "cover_url": null,
          "cover_color": null,
          "notes": null,
          "timezone": "Europe/Lisbon",
          "place_count": 4
        }]
        """)

        let trips = try await api().trips()
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].placeCount, 4)
        XCTAssertEqual(trips[0].timezone, "Europe/Lisbon")
        XCTAssertEqual(trips[0].dayCount, 5)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer jwt-token")
        XCTAssertEqual(request.url?.path, "/v1/trips")
    }

    func testCreateTripPostsSnakeCaseBodyWithIdempotencyKey() async throws {
        respond(201, """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "owner_id": "22222222-2222-4222-8222-222222222222",
          "title": "Tokyo",
          "destination": "Tokyo, Japan",
          "start_date": "2027-03-01",
          "end_date": "2027-03-03",
          "currency": "USD",
          "timezone": "Asia/Tokyo",
          "place_count": 0
        }
        """)

        let draft = NewTripDraft(
            title: "Tokyo",
            destination: "Tokyo, Japan",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_172_800),
            days: 3,
            dateRange: "Mar 1 – 3",
            coverColor: "#223843",
            timezone: "Asia/Tokyo"
        )
        let trip = try await api().createTrip(draft)
        XCTAssertEqual(trip.title, "Tokyo")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "idempotency-key"))
        let body = try XCTUnwrap(request.capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["title"] as? String, "Tokyo")
        XCTAssertEqual(object["timezone"] as? String, "Asia/Tokyo")
        XCTAssertNotNil(object["start_date"])
        XCTAssertNil(object["startDate"])
    }

    func testMissingTokenFailsBeforeTheNetwork() async {
        StubURLProtocol.handler = { _ in
            XCTFail("The request should not leave the device without a token")
            throw URLError(.badURL)
        }
        do {
            _ = try await api(token: nil).trips()
            XCTFail("Expected an authentication error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "not_authenticated")
            XCTAssertTrue(error.isAuthenticationFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerErrorMapsToTypedAPIError() async {
        respond(403, """
        {"error":{"code":"read_only","message":"You have view-only access to this trip."}}
        """)
        do {
            _ = try await api().trips()
            XCTFail("Expected a read-only error")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
            XCTAssertEqual(error.code, "read_only")
            XCTAssertEqual(error.message, "You have view-only access to this trip.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkFailureBecomesOfflineError() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await api().trips()
            XCTFail("Expected an offline error")
        } catch let error as APIError {
            XCTAssertTrue(error.isOffline)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAttachmentURLResolvesAgainstTheAPI() async throws {
        respond(200, #"{"url":"https://api.wanderer.test/media/trips/a/b.pdf?exp=1&sig=abc"}"#)
        let url = try await api().attachmentURL(
            tripID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            attachmentID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        )
        XCTAssertEqual(url.host, "api.wanderer.test")
        XCTAssertEqual(url.path, "/media/trips/a/b.pdf")
    }

    func testTripRecordWithoutPlaceCountStillDecodes() throws {
        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "owner_id": "22222222-2222-4222-8222-222222222222",
          "title": "No digits",
          "currency": "USD",
          "timezone": "UTC"
        }
        """
        let record = try JSONDecoder().decode(TripRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.placeCount, 0)
        XCTAssertEqual(record.dayCount, 0)
    }
}

final class ClerkAuthParsingTests: XCTestCase {
    func testJWTExpiryIsReadFromThePayload() throws {
        // {"exp": 1800000000}
        let payload = "eyJleHAiOjE4MDAwMDAwMDB9"
        let jwt = "header.\(payload).signature"
        let expiry = try XCTUnwrap(ClerkAuthClient.jwtExpiry(jwt))
        XCTAssertEqual(expiry.timeIntervalSince1970, 1_800_000_000, accuracy: 0.01)
    }

    func testJWTExpiryRejectsGarbage() {
        XCTAssertNil(ClerkAuthClient.jwtExpiry("not-a-jwt"))
        XCTAssertNil(ClerkAuthClient.jwtExpiry("a.b.c"))
    }

    func testClerkErrorMessageIsHuman() {
        let object: [String: Any] = [
            "errors": [[
                "code": "form_password_incorrect",
                "message": "Password is incorrect",
                "long_message": "Password is incorrect. Try another password."
            ]]
        ]
        XCTAssertEqual(
            ClerkAuthClient.errorMessage(in: object),
            "That password doesn't match. Try again."
        )
    }

    func testClerkUnknownErrorFallsBackToServerText() {
        let object: [String: Any] = [
            "errors": [["code": "something_else", "message": "Unexpected."]]
        ]
        XCTAssertEqual(ClerkAuthClient.errorMessage(in: object), "Unexpected.")
    }
}
