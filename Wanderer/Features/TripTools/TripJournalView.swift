import MapKit
import SwiftUI

/// The trip after it happened: every stop marked visited, on a map and in
/// the order it was visited. Read-only and derived from place data.
struct TripJournalView: View {
    let trip: Trip
    @ObservedObject var store: TripDetailStore

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    private var visited: [PlaceRecord] {
        store.visitedPlaces
    }

    private var visitedWithCoordinates: [PlaceRecord] {
        visited.filter { $0.coordinate != nil }
    }

    private var visitedByDate: [(label: String, places: [PlaceRecord])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let grouped = Dictionary(grouping: visited) { place -> String in
            guard let stamp = place.visitedAt,
                  let date = ISO8601DateFormatter().date(from: stamp) ?? {
                      let parser = ISO8601DateFormatter()
                      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                      return parser.date(from: stamp)
                  }() else {
                return "Undated"
            }
            return formatter.string(from: date)
        }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none

        return grouped
            .map { key, places in
                let label = formatter.date(from: key).map { display.string(from: $0) } ?? "Undated"
                return (label: label, places: places.sorted { ($0.visitedAt ?? "") < ($1.visitedAt ?? "") })
            }
            .sorted { $0.places.first?.visitedAt ?? "" < $1.places.first?.visitedAt ?? "" }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: LiggaSpace.l) {
                    if visited.isEmpty {
                        emptyState
                    } else {
                        map
                        summary
                        ForEach(Array(visitedByDate.enumerated()), id: \.offset) { _, group in
                            daySection(group)
                        }
                    }
                }
                .padding(.horizontal, WandererTheme.gutter)
                .padding(.vertical, LiggaSpace.m)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Trip journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(Array(visitedWithCoordinates.enumerated()), id: \.element.id) { index, place in
                if let coordinate = place.coordinate {
                    Marker(
                        "\(index + 1). \(place.name)",
                        coordinate: CLLocationCoordinate2D(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    )
                    .tint(WandererTheme.mint)
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { fitMap() }
        .accessibilityLabel("Map of \(visitedWithCoordinates.count) visited stops")
    }

    private var summary: some View {
        HStack(spacing: LiggaSpace.m) {
            stat(value: "\(visited.count)", label: visited.count == 1 ? "stop" : "stops")
            stat(value: "\(visitedByDate.count)", label: visitedByDate.count == 1 ? "day" : "days")
            stat(value: "\(store.places.count - visited.count)", label: "to go")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.ligga(.title2, weight: .bold))
                .foregroundStyle(WandererTheme.ink)
                .monospacedDigit()
            Text(label)
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LiggaSpace.s)
        .liggaCard()
    }

    private func daySection(_ group: (label: String, places: [PlaceRecord])) -> some View {
        VStack(alignment: .leading, spacing: LiggaSpace.xs) {
            Text(group.label)
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(group.places.enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: LiggaSpace.s) {
                        Text("\(index + 1)")
                            .font(.ligga(.caption, weight: .bold))
                            .foregroundStyle(WandererTheme.onPrimary)
                            .frame(width: 22, height: 22)
                            .background(WandererTheme.mint, in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name)
                                .font(.ligga(.body, weight: .semibold))
                                .foregroundStyle(WandererTheme.ink)
                            Text([place.category.title, place.address]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if let time = place.timeLabel(in: trip.timezone) {
                            Text(time)
                                .font(.ligga(.caption2, weight: .semibold))
                                .foregroundStyle(WandererTheme.coralDeep)
                        }
                    }
                    .padding(.vertical, LiggaSpace.s)

                    if index < group.places.count - 1 {
                        Divider().overlay(WandererTheme.line)
                    }
                }
            }
            .padding(.horizontal, LiggaSpace.m)
            .liggaCard()
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiggaSpace.s) {
            Image(systemName: "map.circle")
                .font(.ligga(.largeTitle, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
            Text("No visited stops yet")
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
            Text("Swipe a stop in the planner and tap Visited. It will show up here, in order.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LiggaSpace.xxl)
    }

    private func fitMap() {
        let coordinates = visitedWithCoordinates.compactMap(\.coordinate)
        guard let first = coordinates.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLng = min(minLng, coordinate.longitude)
            maxLng = max(maxLng, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.6),
            longitudeDelta: max(0.02, (maxLng - minLng) * 1.6)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}
