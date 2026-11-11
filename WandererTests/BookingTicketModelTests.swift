import XCTest
@testable import Wanderer

final class BookingTicketModelTests: XCTestCase {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let posix = Locale(identifier: "en_US_POSIX")

    private func reservation(_ type: String, title: String, start: String?, end: String?,
                             from: String? = nil, to: String? = nil) throws -> ReservationRecord {
        let json: [String: Any] = [
            "id": UUID().uuidString, "trip_id": UUID().uuidString, "type": type, "title": title,
            "start_at": start ?? NSNull(), "end_at": end ?? NSNull(),
            "start_location": from ?? NSNull(), "end_location": to ?? NSNull()
        ]
        return try JSONDecoder().decode(ReservationRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testReadsAirportCodesInSeveralSpellings() {
        XCTAssertEqual(BookingTicketModel.codes(in: "NRT → ITM").map { [$0.0, $0.1] }, ["NRT", "ITM"])
        XCTAssertEqual(BookingTicketModel.codes(in: "lis-opo").map { [$0.0, $0.1] }, ["LIS", "OPO"])
        XCTAssertEqual(BookingTicketModel.codes(in: "JFK to SFO").map { [$0.0, $0.1] }, ["JFK", "SFO"])
        XCTAssertNil(BookingTicketModel.codes(in: "Machiya near Gion"))
    }

    func testFlightUsesCodesWithCitiesAndDuration() throws {
        let flight = try reservation("flight", title: "NRT → ITM", start: "2026-11-08T06:00:00Z", end: "2026-11-08T07:20:00Z",
                                     from: "Tokyo Narita", to: "Osaka Itami")
        let model = BookingTicketModel(reservation: flight, timeZone: tokyo, locale: posix)
        XCTAssertEqual(model.origin.mark, "NRT")
        XCTAssertEqual(model.origin.caption, "Tokyo Narita")
        XCTAssertEqual(model.destination?.mark, "ITM")
        XCTAssertEqual(model.span, "1h 20m")
        XCTAssertEqual(model.origin.time?.replacingOccurrences(of: "\u{202F}", with: " "), "3:00 PM")
    }

    func testStayCountsNightsInTheTripTimeZone() throws {
        // 23:00 UTC on the 7th is the 8th in Tokyo; checkout on the 12th = 4 nights.
        let stay = try reservation("lodging", title: "Machiya near Gion", start: "2026-11-07T23:00:00Z", end: "2026-11-12T02:00:00Z")
        let model = BookingTicketModel(reservation: stay, timeZone: tokyo, locale: posix)
        XCTAssertTrue(model.isStay)
        XCTAssertEqual(model.origin.mark, "Nov 8")
        XCTAssertEqual(model.origin.caption, "Check in")
        XCTAssertEqual(model.destination?.mark, "Nov 12")
        XCTAssertEqual(model.destination?.caption, "Check out")
        XCTAssertEqual(model.span, "4 nights")
    }

    func testTrainWithoutCodesUsesPlaceNames() throws {
        let train = try reservation("train", title: "Shinkansen", start: "2026-11-09T00:00:00Z", end: nil,
                                    from: "Kyoto", to: "Tokyo")
        let model = BookingTicketModel(reservation: train, timeZone: tokyo, locale: posix)
        XCTAssertEqual(model.origin.mark, "Kyoto")
        XCTAssertEqual(model.destination?.mark, "Tokyo")
        XCTAssertNil(model.span)
    }

    func testOvernightLegsAreNotGivenAMisleadingDuration() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertNil(BookingTicketModel.duration(from: start, to: start.addingTimeInterval(30 * 3600)))
        XCTAssertNil(BookingTicketModel.duration(from: start, to: start))
    }
}
