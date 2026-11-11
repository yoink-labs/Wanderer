import XCTest
@testable import Wanderer

final class DailySpendTests: XCTestCase {
    private let trip = UUID()

    private func expense(_ amount: Double, on day: String) throws -> ExpenseRecord {
        let json: [String: Any] = [
            "id": UUID().uuidString, "trip_id": trip.uuidString, "title": "x", "amount": amount,
            "currency": "USD", "category": "food", "paid_by": NSNull(), "split_with": [],
            "split_mode": "equal", "spent_at": day
        ]
        return try JSONDecoder().decode(ExpenseRecord.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testGroupsByTripDayAndKeepsOutsideSpendSeparate() throws {
        let days = (0..<3).map { TripDayRecord(id: UUID(), tripId: trip, dayIndex: $0, date: "2026-12-0\($0 + 1)", title: nil, notes: nil) }
        let expenses = [
            try expense(300, on: "2026-10-01"),
            try expense(20, on: "2026-12-01"),
            try expense(15, on: "2026-12-01"),
            try expense(40, on: "2026-12-03"),
            try expense(9, on: "2026-12-09")
        ]
        let series = DailySpend.series(expenses: expenses, days: days)
        XCTAssertEqual(series.map(\.label), ["Before", "1", "2", "3", "After"])
        XCTAssertEqual(series.map(\.amount), [300, 35, 0, 40, 9])
        XCTAssertEqual(series.reduce(0) { $0 + $1.amount }, 384)
    }

    func testNoOutsideBarsWhenEverythingFallsInTheTrip() throws {
        let days = [TripDayRecord(id: UUID(), tripId: trip, dayIndex: 0, date: "2026-12-01", title: nil, notes: nil)]
        let series = DailySpend.series(expenses: [try expense(5, on: "2026-12-01")], days: days)
        XCTAssertEqual(series.map(\.label), ["1"])
    }
}
