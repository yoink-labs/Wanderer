import XCTest
@testable import Wanderer

final class PlannerStartDayTests: XCTestCase {
    private let trip = UUID()

    private func day(_ index: Int, _ date: String?) -> TripDayRecord {
        TripDayRecord(id: UUID(), tripId: trip, dayIndex: index, date: date, title: nil, notes: nil)
    }

    private func place(on dayID: UUID?) throws -> PlaceRecord {
        let json: [String: Any] = [
            "id": UUID().uuidString, "trip_id": trip.uuidString, "name": "Stop",
            "category": "sight", "position": 0, "day_id": dayID?.uuidString ?? NSNull()
        ]
        return try JSONDecoder().decode(PlaceRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testOpensOnTodayDuringTheTrip() throws {
        let days = [day(0, "2026-12-01"), day(1, "2026-12-02"), day(2, "2026-12-03")]
        let today = TripDayRecord.date(from: "2026-12-02")!
        XCTAssertEqual(PlannerStartDay.choose(days: days, places: [], today: today), days[1].id)
    }

    func testOtherwiseFirstPlannedDay() throws {
        let days = [day(0, "2026-12-01"), day(1, "2026-12-02")]
        let places = [try place(on: days[1].id)]
        let today = TripDayRecord.date(from: "2026-11-01")!
        XCTAssertEqual(PlannerStartDay.choose(days: days, places: places, today: today), days[1].id)
    }

    func testFallsBackToDayOneAndNilWithoutDays() {
        let days = [day(1, nil), day(0, nil)]
        XCTAssertEqual(PlannerStartDay.choose(days: days, places: []), days[1].id)
        XCTAssertNil(PlannerStartDay.choose(days: [], places: []))
    }
}
