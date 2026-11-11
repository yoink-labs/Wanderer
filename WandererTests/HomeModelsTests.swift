import XCTest
@testable import Wanderer

final class HomeModelsTests: XCTestCase {
    func testRecentTripsMovesToFrontAndCaps() {
        let ids = (0..<10).map { _ in UUID() }
        var raw = ""
        for id in ids {
            raw = RecentTrips.recording(id, in: raw)
        }
        let decoded = RecentTrips.decode(raw)
        XCTAssertEqual(decoded.count, RecentTrips.limit)
        XCTAssertEqual(decoded.first, ids.last)
    }

    func testSearchIgnoresAccentsAndRequiresAllTokens() {
        let trip = Trip(
            title: "Reykjavík road trip",
            destination: "Reykjavík, Iceland",
            dateRange: "Jun 2 – 9",
            days: 7,
            places: 22,
            members: ["AR"],
            palette: .reykjavik,
            symbol: "mountain.2.fill"
        )

        XCTAssertEqual(HomeSearch.trips([trip], matching: "reykjavik").count, 1)
        XCTAssertEqual(HomeSearch.trips([trip], matching: "reykjavik iceland").count, 1)
        XCTAssertEqual(HomeSearch.trips([trip], matching: "kyoto").count, 0)
    }

    func testOrderingFeaturesTripInProgress() {
        let inProgress = Trip(
            title: "Kyoto in autumn",
            destination: "Kyoto, Japan",
            dateRange: "Nov 6 – 10",
            days: 5,
            places: 7,
            members: ["AR"],
            palette: .kyoto,
            symbol: "leaf.fill",
            startDate: "2026-11-06",
            endDate: "2026-11-10"
        )
        let upcoming = Trip(
            title: "Rio getaway",
            destination: "Rio de Janeiro, Brazil",
            dateRange: "Nov 17 – 27",
            days: 11,
            places: 17,
            members: ["AR"],
            palette: .lagoon,
            symbol: "airplane",
            startDate: "2026-11-17",
            endDate: "2026-11-27"
        )

        let ordering = HomeTripOrdering(
            trips: [upcoming, inProgress],
            recentIDs: [],
            now: TripDayRecord.date(from: "2026-11-08") ?? Date()
        )

        XCTAssertEqual(ordering.featured?.id, inProgress.id)
        XCTAssertEqual(ordering.reason, .inProgress)
        XCTAssertEqual(ordering.others.map(\.id), [upcoming.id])
    }
}

final class TripRouteProgressTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func trip(start: String, days: Int) -> Trip {
        Trip(title: "T", destination: "D", dateRange: "", days: days, places: 0,
             members: [], palette: .lisbon, symbol: "airplane", startDate: start)
    }

    private func date(_ value: String) -> Date {
        TripDayRecord.date(from: value)!
    }

    func testBeforeStartHasNoCurrentDay() {
        let progress = TripRouteProgress(trip: trip(start: "2026-12-01", days: 5), now: date("2026-11-20"), calendar: calendar)
        XCTAssertNil(progress.current)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertEqual(progress.label, "5 days")
    }

    func testMidTripMarksToday() {
        let progress = TripRouteProgress(trip: trip(start: "2026-12-01", days: 5), now: date("2026-12-03"), calendar: calendar)
        XCTAssertEqual(progress.current, 2)
        XCTAssertEqual(progress.completed, 2)
        XCTAssertEqual(progress.label, "Day 3 of 5")
    }

    func testAfterEndIsDone() {
        let progress = TripRouteProgress(trip: trip(start: "2026-12-01", days: 5), now: date("2026-12-10"), calendar: calendar)
        XCTAssertNil(progress.current)
        XCTAssertEqual(progress.completed, 5)
    }

    func testLongTripsDropBeads() {
        let progress = TripRouteProgress(trip: trip(start: "2026-12-01", days: 21), now: date("2026-11-01"), calendar: calendar)
        XCTAssertFalse(progress.showsBeads)
    }
}
