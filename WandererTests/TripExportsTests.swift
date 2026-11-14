import XCTest
@testable import Wanderer

final class TripExportsTests: XCTestCase {
    func testCalendarFileIncludesPlacesAndReservations() throws {
        let trip = Trip.samples[0]
        let dayID = UUID()
        let place = PlaceRecord(
            id: UUID(),
            tripId: trip.id,
            dayId: dayID,
            name: "Café, with commas; and a semicolon",
            address: "Rua da Prata 1",
            lat: 38.7,
            lng: -9.1,
            category: .food,
            notes: "Try the custard tart",
            website: nil,
            phone: nil,
            priceLevel: nil,
            rating: nil,
            photoUrl: nil,
            startTime: nil,
            endTime: nil,
            position: 0,
            createdBy: nil
        )
        let day = TripDayRecord(
            id: dayID,
            tripId: trip.id,
            dayIndex: 0,
            date: "2026-11-12",
            title: nil,
            notes: nil
        )
        let reservation = ReservationRecord(
            id: UUID(),
            tripId: trip.id,
            type: .flight,
            title: "BA123",
            provider: "British Airways",
            confirmationCode: "ABC123",
            startAt: "2026-11-12T09:00:00Z",
            endAt: "2026-11-12T11:30:00Z",
            startLocation: "LHR",
            endLocation: "LIS",
            cost: nil,
            currency: nil,
            notes: nil
        )

        let ics = TripExports.ics(
            trip: trip,
            days: [day],
            places: [place],
            reservations: [reservation]
        )

        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("BEGIN:VEVENT"))
        XCTAssertTrue(ics.contains("SUMMARY:Flight: BA123"))
        XCTAssertTrue(ics.contains("SUMMARY:Café\\, with commas\\; and a semicolon"))
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20261112"))
        XCTAssertTrue(ics.contains("LOCATION:Rua da Prata 1"))
    }

    func testCalendarSkipsUndatedPlaces() {
        let trip = Trip.samples[0]
        let place = PlaceRecord(
            id: UUID(),
            tripId: trip.id,
            dayId: nil,
            name: "Nowhere",
            address: nil,
            lat: nil,
            lng: nil,
            category: .note,
            notes: nil,
            website: nil,
            phone: nil,
            priceLevel: nil,
            rating: nil,
            photoUrl: nil,
            startTime: nil,
            endTime: nil,
            position: 0,
            createdBy: nil
        )
        let ics = TripExports.ics(trip: trip, days: [], places: [place], reservations: [])
        XCTAssertFalse(ics.contains("SUMMARY:Nowhere"))
    }

    func testGoogleMapsURLUsesOriginDestinationAndWaypoints() throws {
        let places = [
            makePlace(lat: 38.71, lng: -9.14),
            makePlace(lat: 38.72, lng: -9.15),
            makePlace(lat: 38.73, lng: -9.16)
        ]
        let urls = TripExports.googleMapsURLs(places: places)
        XCTAssertEqual(urls.count, 1)
        let components = try XCTUnwrap(URLComponents(url: urls[0], resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["origin"], "38.71,-9.14")
        XCTAssertEqual(items["destination"], "38.73,-9.16")
        XCTAssertEqual(items["waypoints"], "38.72,-9.15")
        XCTAssertEqual(items["travelmode"], "walking")
    }

    func testGoogleMapsChunksLongDays() {
        let places = (0..<25).map { makePlace(lat: 38.7 + Double($0) / 1000, lng: -9.1) }
        let urls = TripExports.googleMapsURLs(places: places)
        XCTAssertEqual(urls.count, 3)
    }

    private func makePlace(lat: Double, lng: Double) -> PlaceRecord {
        PlaceRecord(
            id: UUID(),
            tripId: UUID(),
            dayId: nil,
            name: "Stop",
            address: nil,
            lat: lat,
            lng: lng,
            category: .sight,
            notes: nil,
            website: nil,
            phone: nil,
            priceLevel: nil,
            rating: nil,
            photoUrl: nil,
            startTime: nil,
            endTime: nil,
            position: 0,
            createdBy: nil
        )
    }
}
