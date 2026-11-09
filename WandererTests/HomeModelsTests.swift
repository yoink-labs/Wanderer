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
