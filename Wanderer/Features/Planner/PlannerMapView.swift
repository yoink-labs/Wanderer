import MapKit
import SwiftUI

extension PlaceRecord {
    /// The place's location bridged to MapKit, or `nil` when it has no pin yet.
    var mapCoordinate: CLLocationCoordinate2D? {
        guard let coordinate else { return nil }
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// The full-bleed itinerary map. The selected day gets numbered pins and a
/// solid route; the rest of the trip is a quiet layer of charcoal dots.
struct PlannerMapView: View {
    let selectedPlaces: [PlaceRecord]
    let otherPlaces: [PlaceRecord]
    @Binding var cameraPosition: MapCameraPosition
    /// The stop highlighted in both the map and the itinerary.
    let focusedPlaceID: UUID?
    var onSelectPlace: (PlaceRecord) -> Void = { _ in }
    var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }

    @State private var metersPerPoint: Double = 0
    @State private var mapHeight: CGFloat = 0

    /// Stop number comes from the itinerary order, including places with no pin,
    /// so map numbers always match the list.
    private var locatedSelected: [PlannerPinItem] {
        selectedPlaces.enumerated().compactMap { index, place in
            guard let coordinate = place.mapCoordinate else { return nil }
            return PlannerPinItem(number: index + 1, place: place, coordinate: coordinate)
        }
    }

    private var locatedOthers: [PlaceRecord] {
        otherPlaces.filter { $0.mapCoordinate != nil }
    }

    private var legs: [(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)] {
        let route = locatedSelected.map(\.coordinate)
        guard route.count > 1 else { return [] }
        return (1..<route.count).map { (route[$0 - 1], route[$0]) }
    }

    /// Pin positions, spread apart when stops overlap at the current zoom.
    private var displayCoordinates: [UUID: CLLocationCoordinate2D] {
        PlannerGeometry.displayCoordinates(
            for: locatedSelected.map { (id: $0.id, coordinate: $0.coordinate) },
            metersPerPoint: metersPerPoint
        )
    }

    var body: some View {
        let display = displayCoordinates

        Map(position: $cameraPosition) {
            ForEach(locatedOthers) { place in
                if let coordinate = place.mapCoordinate {
                    Annotation("", coordinate: coordinate, anchor: .center) {
                        Circle()
                            .fill(WandererTheme.charcoal.opacity(0.28))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                    .annotationTitles(.hidden)
                }
            }

            // Routes always use exact coordinates, never the spread display ones.
            ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(coordinates: [leg.start, leg.end])
                    .stroke(
                        WandererTheme.peach.opacity(isLongTransfer(leg) ? 0.55 : 1),
                        style: StrokeStyle(
                            lineWidth: isLongTransfer(leg) ? 2 : 3,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: isLongTransfer(leg) ? [6, 8] : []
                        )
                    )
            }

            ForEach(locatedSelected) { item in
                Annotation(
                    item.place.name,
                    coordinate: display[item.place.id] ?? item.coordinate,
                    anchor: .center
                ) {
                    Button {
                        onSelectPlace(item.place)
                    } label: {
                        PlannerMapPin(number: item.number, isSelected: focusedPlaceID == item.id)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .overlay(alignment: .top) {
                                if focusedPlaceID == item.id {
                                    PlannerPinCallout(name: item.place.name)
                                        .offset(y: -30)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop \(item.number), \(item.place.name), \(item.place.category.title)")
                    .accessibilityHint(focusedPlaceID == item.id ? "Opens place details" : "Highlights this stop in the itinerary")
                    .accessibilityAddTraits(focusedPlaceID == item.id ? .isSelected : [])
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(
            elevation: .flat,
            emphasis: .muted,
            pointsOfInterest: .excludingAll,
            showsTraffic: false
        ))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            mapHeight = height
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            metersPerPoint = PlannerGeometry.metersPerPoint(for: context.region, height: mapHeight)
            onRegionChange(context.region)
        }
        .accessibilityIdentifier("planner-map")
    }

    /// A long leg is a transfer, not a walk. Dashed keeps it from reading as a
    /// road route while still showing the day's order.
    private func isLongTransfer(_ leg: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)) -> Bool {
        PlannerGeometry.meters(from: leg.start, to: leg.end) > 3_000
    }
}

private struct PlannerPinItem: Identifiable {
    let number: Int
    let place: PlaceRecord
    let coordinate: CLLocationCoordinate2D

    var id: UUID { place.id }
}

/// Map pin in fixed Atlas colours so it reads on light and dark maps alike:
/// a marigold bead with an ink number, flipping to ink with a marigold ring
/// when selected.
private struct PlannerMapPin: View {
    let number: Int
    let isSelected: Bool

    private static let marigold = Color(hex: 0xF2A922)
    private static let ink = Color(hex: 0x10283A)

    var body: some View {
        let size: CGFloat = isSelected ? 38 : 30
        ZStack {
            Circle()
                .fill(isSelected ? Self.ink : Self.marigold)
                .overlay(Circle().strokeBorder(isSelected ? Self.marigold : .white, lineWidth: isSelected ? 3 : 2))
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            Text("\(number)")
                .font(.system(size: isSelected ? 16 : 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Self.marigold : Self.ink)
                .padding(.horizontal, 3)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
    }
}

/// Name label above the highlighted pin.
private struct PlannerPinCallout: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.ligga(.footnote, weight: .semibold))
            .foregroundStyle(WandererTheme.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: WandererTheme.charcoal.opacity(0.18), radius: 8, x: 0, y: 3)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

#Preview {
    PlannerMapView(
        selectedPlaces: [],
        otherPlaces: [],
        cameraPosition: .constant(.automatic),
        focusedPlaceID: nil
    )
}
