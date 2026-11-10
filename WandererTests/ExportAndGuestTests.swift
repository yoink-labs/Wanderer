import XCTest
@testable import Wanderer

final class ExportAndGuestTests: XCTestCase {
    private func sampleTrip() -> Trip {
        Trip(
            title: "Kyoto in autumn",
            destination: "Kyoto, Japan",
            dateRange: "Nov 12 – 17",
            days: 5,
            places: 2,
            members: ["AR"],
            palette: .kyoto,
            symbol: "leaf.fill",
            startDate: "2026-11-12",
            endDate: "2026-11-16",
            timezone: "Asia/Tokyo"
        )
    }

    func testTripSurvivesJSONRoundTripForGuestStorage() throws {
        let trip = sampleTrip()
        let data = try JSONEncoder().encode([trip])
        let decoded = try JSONDecoder().decode([Trip].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, trip.id)
        XCTAssertEqual(decoded[0].title, trip.title)
        XCTAssertEqual(decoded[0].palette, trip.palette)
        XCTAssertEqual(decoded[0].timezone, "Asia/Tokyo")
        XCTAssertEqual(decoded[0].startDate, "2026-11-12")
    }

    func testGuestDraftUsesTheStoredDates() {
        let draft = sampleTrip().guestDraft
        XCTAssertEqual(draft.title, "Kyoto in autumn")
        XCTAssertEqual(draft.days, 5)
        XCTAssertEqual(NewTripDraft.apiDate(draft.startDate), "2026-11-12")
        XCTAssertEqual(NewTripDraft.apiDate(draft.endDate), "2026-11-16")
    }

    func testPDFExporterProducesAReadablePDF() {
        let trip = sampleTrip()
        let dayID = UUID()
        let day = TripDayRecord(id: dayID, tripId: trip.id, dayIndex: 0, date: "2026-11-12", title: nil, notes: "Arrive late")
        let place = PlaceRecord(
            id: UUID(),
            tripId: trip.id,
            dayId: dayID,
            name: "Fushimi Inari Shrine",
            address: "Kyoto",
            lat: 34.9671,
            lng: 135.7727,
            category: .sight,
            notes: nil,
            website: nil,
            phone: nil,
            priceLevel: nil,
            rating: 4.8,
            photoUrl: nil,
            startTime: nil,
            endTime: nil,
            position: 0,
            visitedAt: nil,
            listId: nil,
            createdBy: nil
        )
        let data = TripPDFExporter.makePDF(
            trip: trip,
            days: [day],
            places: [place],
            reservations: [],
            expenses: []
        )
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }

    func testPDFExporterHandlesAnEmptyTrip() {
        let data = TripPDFExporter.makePDF(
            trip: sampleTrip(),
            days: [],
            places: [],
            reservations: [],
            expenses: []
        )
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }
}
