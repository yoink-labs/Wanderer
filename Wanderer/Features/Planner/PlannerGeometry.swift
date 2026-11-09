import MapKit
import SwiftUI

/// Offline geometry for the planner: straight-line distances, rough travel
/// estimates, camera fitting against the visible map strip, and pin spreading
/// for stops that sit on top of each other. Nothing here touches the network.
enum PlannerGeometry {
    static let metersPerDegreeLatitude = 111_320.0

    /// Great-circle distance in meters.
    static func meters(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLat = (end.latitude - start.latitude) * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    static func metersPerDegreeLongitude(at latitude: Double) -> Double {
        max(1, metersPerDegreeLatitude * cos(latitude * .pi / 180))
    }

    // MARK: - Camera

    /// A region that shows every coordinate inside `insets` of a map of `size`
    /// (the map is full-bleed, so insets carve out the sheet and top controls).
    static func fittingRegion(
        for coordinates: [CLLocationCoordinate2D],
        in size: CGSize,
        insets: EdgeInsets,
        minimumMeters: Double = 900
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLng = longitudes.min(), let maxLng = longitudes.max() else {
            return nil
        }

        let midLat = (minLat + maxLat) / 2
        let lngScale = metersPerDegreeLongitude(at: midLat)
        let boxHeight = max((maxLat - minLat) * metersPerDegreeLatitude, minimumMeters)
        let boxWidth = max((maxLng - minLng) * lngScale, minimumMeters)

        let available = availableSize(in: size, insets: insets)
        let metersPerPoint = max(boxWidth / available.width, boxHeight / available.height)

        return region(
            placing: CLLocationCoordinate2D(latitude: midLat, longitude: (minLng + maxLng) / 2),
            metersPerPoint: metersPerPoint,
            in: size,
            insets: insets
        )
    }

    /// A region at the given zoom that puts `coordinate` in the middle of the
    /// visible strip described by `insets`.
    static func region(
        placing coordinate: CLLocationCoordinate2D,
        metersPerPoint: Double,
        in size: CGSize,
        insets: EdgeInsets
    ) -> MKCoordinateRegion {
        let lngScale = metersPerDegreeLongitude(at: coordinate.latitude)
        let available = availableSize(in: size, insets: insets)
        let targetX = insets.leading + available.width / 2
        let targetY = insets.top + available.height / 2

        // Screen y grows downward: a target above the middle means the region
        // center must sit south of the coordinate.
        let centerLat = coordinate.latitude + (targetY - size.height / 2) * metersPerPoint / metersPerDegreeLatitude
        let centerLng = coordinate.longitude - (targetX - size.width / 2) * metersPerPoint / lngScale

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: min(max(centerLat, -85), 85),
                longitude: centerLng
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(metersPerPoint * size.height / metersPerDegreeLatitude, 170),
                longitudeDelta: min(metersPerPoint * size.width / lngScale, 350)
            )
        )
    }

    /// Meters per screen point for a region shown in a map `height` points tall.
    static func metersPerPoint(for region: MKCoordinateRegion, height: CGFloat) -> Double {
        guard height > 0 else { return 0 }
        return region.span.latitudeDelta * metersPerDegreeLatitude / Double(height)
    }

    private static func availableSize(in size: CGSize, insets: EdgeInsets) -> CGSize {
        CGSize(
            width: max(size.width - insets.leading - insets.trailing, 80),
            height: max(size.height - insets.top - insets.bottom, 80)
        )
    }

    // MARK: - Pin spreading

    /// Display positions for pins. Stops closer than `max(150 m, one pin width
    /// on screen)` are pushed apart around their shared center so every number
    /// stays visible and tappable. Exact coordinates are untouched; callers keep
    /// using them for routes and distances.
    static func displayCoordinates(
        for places: [(id: UUID, coordinate: CLLocationCoordinate2D)],
        metersPerPoint: Double,
        pinDiameter: Double = 34
    ) -> [UUID: CLLocationCoordinate2D] {
        var result: [UUID: CLLocationCoordinate2D] = [:]
        for place in places {
            result[place.id] = place.coordinate
        }
        guard places.count > 1 else { return result }

        let mpp = max(metersPerPoint, 0)
        let threshold = max(150, pinDiameter * mpp)

        // Single-link grouping: anything within the threshold of a group member
        // joins that group.
        var groupOf = Array(0..<places.count)
        func root(_ index: Int) -> Int {
            var node = index
            while groupOf[node] != node { node = groupOf[node] }
            return node
        }
        for i in 0..<places.count {
            for j in (i + 1)..<places.count
            where meters(from: places[i].coordinate, to: places[j].coordinate) < threshold {
                let left = root(i)
                let right = root(j)
                if left != right { groupOf[right] = left }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in 0..<places.count {
            groups[root(index), default: []].append(index)
        }

        for members in groups.values where members.count > 1 {
            let count = Double(members.count)
            let centerLat = members.map { places[$0].coordinate.latitude }.reduce(0, +) / count
            let centerLng = members.map { places[$0].coordinate.longitude }.reduce(0, +) / count
            let lngScale = metersPerDegreeLongitude(at: centerLat)

            // Ring radius so neighbours sit one pin apart (plus a little air).
            let ringPoints = (pinDiameter * 0.56) / sin(.pi / count)
            let ringMeters = ringPoints * mpp

            for (order, index) in members.enumerated() {
                let coordinate = places[index].coordinate
                var dx = (coordinate.longitude - centerLng) * lngScale
                var dy = (coordinate.latitude - centerLat) * metersPerDegreeLatitude
                let length = sqrt(dx * dx + dy * dy)

                if length < 1 {
                    // Same spot: fan out clockwise from 12 o'clock in stop order.
                    let angle = -Double.pi / 2 + 2 * .pi * Double(order) / count
                    dx = cos(angle)
                    dy = -sin(angle)
                } else {
                    dx /= length
                    dy /= length
                }

                let distance = max(length, ringMeters)
                result[places[index].id] = CLLocationCoordinate2D(
                    latitude: centerLat + dy * distance / metersPerDegreeLatitude,
                    longitude: centerLng + dx * distance / lngScale
                )
            }
        }

        return result
    }
}

// MARK: - Travel legs

/// A rough, offline estimate of getting from one stop to the next.
struct PlannerTravelLeg: Equatable {
    enum Mode: Equatable {
        case walk
        case drive
        case transfer

        var symbol: String {
            switch self {
            case .walk: return "figure.walk"
            case .drive: return "car.fill"
            case .transfer: return "airplane"
            }
        }

        var noun: String {
            switch self {
            case .walk: return "walk"
            case .drive: return "drive"
            case .transfer: return "transfer"
            }
        }
    }

    let meters: Double
    let mode: Mode
    let minutes: Int?

    /// Straight-line distance, inflated by a typical street-grid detour for the
    /// time estimate. Walk up to ~1.2 km, drive up to 100 km, beyond that it is a
    /// long transfer we don't pretend to time.
    init(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) {
        let straight = PlannerGeometry.meters(from: start, to: end)
        meters = straight
        let road = straight * 1.3

        if straight <= 1_200 {
            mode = .walk
            minutes = max(1, Int((road / 80).rounded()))
        } else if straight <= 100_000 {
            mode = .drive
            let metersPerMinute = straight < 15_000 ? 450.0 : 1_000.0
            minutes = Int((road / metersPerMinute).rounded()) + 4
        } else {
            mode = .transfer
            minutes = nil
        }
    }

    var summary: String {
        let distance = PlannerDistanceFormat.string(meters)
        guard let minutes else { return "Long transfer · \(distance)" }
        return "\(PlannerDistanceFormat.duration(minutes)) \(mode.noun) · \(distance)"
    }

    var accessibilitySummary: String {
        let distance = PlannerDistanceFormat.string(meters)
        guard let minutes else { return "Long transfer, \(distance) in a straight line" }
        return "About \(PlannerDistanceFormat.duration(minutes)) \(mode.noun), \(distance) in a straight line"
    }
}

enum PlannerDistanceFormat {
    static var usesMiles: Bool {
        Locale.current.measurementSystem == .us
    }

    static func string(_ meters: Double) -> String {
        if usesMiles {
            let miles = meters / 1_609.344
            if miles < 0.1 { return "\(max(10, Int((meters * 3.28084 / 10).rounded()) * 10)) ft" }
            return miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
        }
        if meters < 1_000 {
            return "\(max(10, Int((meters / 10).rounded()) * 10)) m"
        }
        let kilometers = meters / 1_000
        return kilometers < 10 ? String(format: "%.1f km", kilometers) : "\(Int(kilometers.rounded())) km"
    }

    static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}
