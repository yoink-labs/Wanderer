import Foundation

@MainActor
final class TripsStore: ObservableObject {
    @Published private(set) var trips: [TripRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let backing: TripsBacking

    init(backing: TripsBacking? = nil) {
        self.backing = backing ?? (LocalTrips.isActive ? GuestTripsBacking() : CloudTripsBacking())
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Trips someone invited this email to join appear without a link.
        if !LocalTrips.isActive, let api = CloudSession.shared.api {
            _ = try? await api.claimInvites()
        }
        do {
            trips = try await backing.load()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your trips: \(error.localizedDescription)"
        }
    }

    func create(_ draft: NewTripDraft) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let record = try await backing.create(draft)
            trips.insert(record, at: 0)
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        } catch {
            errorMessage = "Couldn't create the trip: \(error.localizedDescription)"
        }
    }

    func update(_ trip: Trip, title: String, destination: String, startDate: Date, endDate: Date) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let updated = try await backing.update(
                trip,
                title: title,
                destination: destination,
                startDate: startDate,
                endDate: endDate
            )
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updated
            }
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        } catch {
            errorMessage = "Couldn't save the trip: \(error.localizedDescription)"
        }
    }

    func updateCover(_ trip: Trip, imageData: Data) async -> String? {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let cover = try await backing.updateCover(trip, imageData: imageData)
            if let cover, let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index].coverUrl = cover
            }
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
            return cover
        } catch {
            errorMessage = "Couldn't update the cover: \(error.localizedDescription)"
            return nil
        }
    }

    func updateNotes(_ trip: Trip, notes: String) async {
        errorMessage = nil
        do {
            let updated = try await backing.updateNotes(trip, notes: notes)
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = updated
            }
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        } catch {
            errorMessage = "Couldn't save the notes: \(error.localizedDescription)"
        }
    }

    func delete(_ trip: Trip) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await backing.delete(trip)
            trips.removeAll { $0.id == trip.id }
            NotificationCenter.default.post(name: .tripsChanged, object: nil)
        } catch {
            errorMessage = "Couldn't delete the trip: \(error.localizedDescription)"
        }
    }
}

struct NewTripDraft {
    let title: String
    let destination: String
    let startDate: Date
    let endDate: Date
    let days: Int
    let dateRange: String
    let coverColor: String
    let timezone: String

    func asLocalTrip(memberInitials: [String]) -> Trip {
        Trip(
            title: title,
            destination: destination,
            dateRange: dateRange,
            days: days,
            places: 0,
            members: memberInitials,
            palette: TripPalette.allCases.randomElement() ?? .lagoon,
            symbol: "airplane",
            timezone: timezone
        )
    }
}
