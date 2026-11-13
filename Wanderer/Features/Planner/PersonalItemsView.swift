import SwiftUI

/// The one place that explains the personal layer: what this member hid,
/// what they changed, and what only they added. Everything here is reversible.
struct PersonalItemsView: View {
    @ObservedObject var store: TripDetailStore
    @Environment(\.dismiss) private var dismiss

    private var hiddenPlaces: [PlaceRecord] {
        let hidden = Set(store.personal.overrides.filter { $0.hidden && $0.itemType == "place" }.map { $0.itemId.lowercased() })
        return store.places.filter { hidden.contains($0.id.uuidString.lowercased()) }
    }

    private var hiddenReservations: [ReservationRecord] {
        let hidden = Set(store.personal.overrides.filter { $0.hidden && $0.itemType == "reservation" }.map { $0.itemId.lowercased() })
        return store.reservations.filter { hidden.contains($0.id.uuidString.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.personal.privatePlaces.isEmpty {
                    Section {
                        ForEach(store.personal.privatePlaces) { place in
                            row(icon: place.category.icon, title: place.name, subtitle: "Private stop")
                        }
                        .onDelete { offsets in
                            let places = store.personal.privatePlaces
                            for index in offsets {
                                Task { await store.deletePrivatePlace(places[index]) }
                            }
                        }
                    } header: {
                        sectionHeader("Only you added", "These stops never appear in anyone else's plan.")
                    }
                }

                if !store.personal.privateReservations.isEmpty {
                    Section {
                        ForEach(store.personal.privateReservations) { reservation in
                            row(icon: reservation.type.icon, title: reservation.title, subtitle: "Private booking")
                        }
                        .onDelete { offsets in
                            let items = store.personal.privateReservations
                            for index in offsets {
                                Task { await store.deletePrivateReservation(items[index]) }
                            }
                        }
                    } header: {
                        sectionHeader("Only your bookings", "Your flight or stay, not the group's.")
                    }
                }

                if !hiddenPlaces.isEmpty {
                    Section {
                        ForEach(hiddenPlaces) { place in
                            HStack {
                                row(icon: place.category.icon, title: place.name, subtitle: "Hidden for you")
                                Button("Restore") {
                                    Task { await store.restoreForMe(place) }
                                }
                                .font(.ligga(.subheadline, weight: .semibold))
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        sectionHeader("Hidden stops", "Still in the group plan; out of your way.")
                    }
                }

                if !hiddenReservations.isEmpty {
                    Section {
                        ForEach(hiddenReservations) { reservation in
                            HStack {
                                row(icon: reservation.type.icon, title: reservation.title, subtitle: "Hidden for you")
                                Button("Restore") {
                                    Task { await store.restoreReservationForMe(reservation) }
                                }
                                .font(.ligga(.subheadline, weight: .semibold))
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        sectionHeader("Hidden bookings", "Still in the group plan; out of your way.")
                    }
                }

                if store.personal.overrides.isEmpty
                    && store.personal.privatePlaces.isEmpty
                    && store.personal.privateReservations.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing private yet", systemImage: "person.crop.circle")
                    } description: {
                        Text("Open a stop to hide it or save your own version. Add a place with “Only visible to me” on.")
                    }
                } else {
                    Section {
                        Text("Private items are yours alone. Removing one here never changes the group plan.")
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("Only you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(WandererTheme.controlTint)
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        SectionHeader(title: title, subtitle: subtitle)
            .textCase(nil)
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                Text(subtitle)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
            }
        }
    }
}
