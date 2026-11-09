import MapKit
import SwiftUI
import XCTest
@testable import Wanderer

final class PlannerGeometryTests: XCTestCase {
    func testDistanceBetweenKnownCoordinates() {
        let copacabana = CLLocationCoordinate2D(latitude: -22.9711, longitude: -43.1822)
        let lapa = CLLocationCoordinate2D(latitude: -22.9134, longitude: -43.1797)
        let meters = PlannerGeometry.meters(from: copacabana, to: lapa)
        XCTAssertGreaterThan(meters, 6_000)
        XCTAssertLessThan(meters, 7_500)
    }

    func testClosePinsAreSpreadApart() {
        let a = UUID()
        let b = UUID()
        let base = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0)
        let near = CLLocationCoordinate2D(latitude: 35.0001, longitude: 135.0001)

        let positions = PlannerGeometry.displayCoordinates(
            for: [(a, base), (b, near)],
            metersPerPoint: 2
        )

        let distance = PlannerGeometry.meters(
            from: positions[a] ?? base,
            to: positions[b] ?? near
        )
        // At 2 m/point the two display positions are about one pin apart.
        XCTAssertGreaterThan(distance, 50)
    }

    func testFittingRegionContainsEveryCoordinate() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: -22.9711, longitude: -43.1822),
            CLLocationCoordinate2D(latitude: -22.9134, longitude: -43.1797),
            CLLocationCoordinate2D(latitude: -22.8789, longitude: -43.4181)
        ]
        let region = PlannerGeometry.fittingRegion(
            for: coordinates,
            in: CGSize(width: 402, height: 874),
            insets: EdgeInsets(top: 80, leading: 20, bottom: 480, trailing: 20)
        )
        XCTAssertNotNil(region)
        guard let region else { return }
        for coordinate in coordinates {
            XCTAssertTrue(
                abs(coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta,
                "Latitude \(coordinate.latitude) outside fitted region"
            )
            XCTAssertTrue(
                abs(coordinate.longitude - region.center.longitude) <= region.span.longitudeDelta,
                "Longitude \(coordinate.longitude) outside fitted region"
            )
        }
    }
}
