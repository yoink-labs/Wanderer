import MapKit
import SwiftUI

struct NearbyIdeasView: View {
    let trip: Trip
    @ObservedObject var store: TripDetailStore
    let dayID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var results: [MapSearchResult] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var addedNames: Set<String> = []

    private var dayLabel: String {
        guard let dayID, let day = store.days.first(where: { $0.id == dayID }) else {
            return "this trip"
        }
        return day.fullDateLabel
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nearby ideas")
                            .font(.ligga(.title2, weight: .bold))
                            .foregroundStyle(WandererTheme.ink)
                        Text("Apple Maps places around \(dayLabel). Tap add to put one in the day.")
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                    }

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(WandererTheme.peach)
                            Text("Looking around the day…")
                                .font(.ligga(.subheadline))
                                .foregroundStyle(WandererTheme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let errorText {
                        VStack(spacing: 10) {
                            Text(errorText)
                                .font(.ligga(.subheadline))
                                .foregroundStyle(WandererTheme.muted)
                                .multilineTextAlignment(.center)
                            Button("Try again") {
                                Task { await load() }
                            }
                            .font(.ligga(.headline, weight: .semibold))
                            .foregroundStyle(WandererTheme.coralDeep)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if results.isEmpty {
                        Text("No suggestions nearby. Try adding a place directly.")
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(results) { result in
                                row(result)
                            }
                        }
                    }

                    Text("Suggestions come from Apple Maps around the day's pins.")
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .padding(.top, 4)
                }
                .padding(WandererTheme.screenPadding)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func row(_ result: MapSearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.category.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.ligga(.headline))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                Text([result.category.title, result.address].compactMap { $0 }.joined(separator: " · "))
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                Task { await add(result) }
            } label: {
                Image(systemName: addedNames.contains(result.name) ? "checkmark" : "plus")
                    .font(.ligga(.footnote, weight: .bold))
                    .foregroundStyle(addedNames.contains(result.name) ? WandererTheme.charcoal : .white)
                    .frame(width: 30, height: 30)
                    .background(
                        addedNames.contains(result.name) ? WandererTheme.dust : WandererTheme.charcoal,
                        in: Circle()
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(addedNames.contains(result.name))
            .accessibilityLabel(addedNames.contains(result.name) ? "\(result.name) added" : "Add \(result.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WandererTheme.line.opacity(0.7), lineWidth: 1)
        )
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let center = try await centerCoordinate()
            var candidates: [MapSearchResult] = []
            if let center {
                candidates += try await MapSearchService.search("things to do", near: center)
                candidates += try await MapSearchService.search("restaurants", near: center)
            } else {
                candidates = try await MapSearchService.search(trip.destination, near: nil)
            }

            let existing = Set(store.places.map { $0.name.lowercased() })
            var seen: Set<String> = []
            results = candidates.filter { result in
                let key = result.name.lowercased()
                guard !existing.contains(key), !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .prefix(10)
            .map { $0 }
        } catch {
            errorText = "Couldn't load nearby ideas: \(error.localizedDescription)"
        }
    }

    private func centerCoordinate() async throws -> CLLocationCoordinate2D? {
        let coordinates = store.places(for: dayID).compactMap(\.coordinate)
        if !coordinates.isEmpty {
            let latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
            let longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let results = try await MapSearchService.search(trip.destination, near: nil)
        return results.first?.coordinate
    }

    private func add(_ result: MapSearchResult) async {
        await store.addPlace(
            name: result.name,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            category: result.category,
            dayID: dayID,
            website: result.website,
            phone: result.phone
        )
        addedNames.insert(result.name)
    }
}
