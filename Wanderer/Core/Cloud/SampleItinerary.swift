import Foundation

/// Real content for the built-in sample trips.
///
/// A first-run trip used to open as an empty shell that claimed "14 places"
/// and had none. These itineraries fill the samples with actual stops, notes,
/// times and bookings, so the app shows what a planned trip looks like before
/// anyone signs in.
enum SampleItinerary {
    struct Stop {
        let dayIndex: Int
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let category: PlaceCategory
        let notes: String?
        /// Minutes from midnight on that day, in the trip's local time.
        let startMinute: Int?
    }

    struct Booking {
        let type: String
        let title: String
        let provider: String?
        let confirmation: String?
        let dayIndex: Int
        let startMinute: Int
        let durationMinutes: Int
        let startLocation: String?
        let endLocation: String?
        let cost: Double?
        let currency: String?
        let metadata: [String: String]?
    }

    struct Plan {
        let stops: [Stop]
        let bookings: [Booking]
    }

    /// Sample trips are matched by their fixed id, not by title.
    static func plan(for trip: Trip) -> Plan? {
        guard trip.destination.localizedCaseInsensitiveContains("Argentina") else { return nil }
        return argentina
    }

    static func isSample(_ trip: Trip) -> Bool {
        Trip.samples.contains { $0.id == trip.id }
    }

    // MARK: - Argentina: Buenos Aires + Iguazú

    static let argentina = Plan(
        stops: [
            // Day 1 — Plaza de Mayo and the old centre.
            Stop(dayIndex: 0, name: "Casa Rosada", address: "Balcarce 78, Monserrat", latitude: -34.6083, longitude: -58.3712, category: .sight, notes: "Free guided tours on weekends — bring ID.", startMinute: 9 * 60),
            Stop(dayIndex: 0, name: "Catedral Metropolitana", address: "San Martín 27, Monserrat", latitude: -34.6075, longitude: -58.3735, category: .sight, notes: "San Martín's tomb is in the side chapel.", startMinute: 10 * 60 + 30),
            Stop(dayIndex: 0, name: "Café Tortoni", address: "Av. de Mayo 825", latitude: -34.6087, longitude: -58.3862, category: .food, notes: "Order a submarino; the queue moves fast at 11.", startMinute: 12 * 60),
            Stop(dayIndex: 0, name: "Teatro Colón", address: "Cerrito 628", latitude: -34.6011, longitude: -58.3833, category: .activity, notes: "Book the 15:00 guided tour online the day before.", startMinute: 15 * 60),
            Stop(dayIndex: 0, name: "El Sanjuanino", address: "Posadas 1515, Recoleta", latitude: -34.5895, longitude: -58.3925, category: .food, notes: "Empanadas and a milanesa — cash is easier.", startMinute: 20 * 60),

            // Day 2 — San Telmo and La Boca.
            Stop(dayIndex: 1, name: "Mercado de San Telmo", address: "Carlos Calvo 400", latitude: -34.6212, longitude: -58.3722, category: .food, notes: "Go hungry; the stalls close around 16:00.", startMinute: 10 * 60),
            Stop(dayIndex: 1, name: "Plaza Dorrego", address: "Defensa y Humberto 1º", latitude: -34.6215, longitude: -58.3714, category: .sight, notes: "Sunday antique market is the big one.", startMinute: 11 * 60 + 30),
            Stop(dayIndex: 1, name: "Caminito", address: "La Boca", latitude: -34.6395, longitude: -58.3640, category: .sight, notes: "Stay on the main strip and keep phones out of sight.", startMinute: 14 * 60),
            Stop(dayIndex: 1, name: "Usina del Arte", address: "Agustín R. Caffarena 1, La Boca", latitude: -34.6375, longitude: -58.3610, category: .activity, notes: "Free exhibitions in the old power station.", startMinute: 16 * 60),
            Stop(dayIndex: 1, name: "El Obrero", address: "Agustín R. Caffarena 64, La Boca", latitude: -34.6387, longitude: -58.3650, category: .food, notes: "Old-school bodegón; no reservations.", startMinute: 19 * 60 + 30),

            // Day 3 — Recoleta and Palermo.
            Stop(dayIndex: 2, name: "Cementerio de la Recoleta", address: "Junín 1760", latitude: -34.5875, longitude: -58.3931, category: .sight, notes: "Evita's tomb is 3 rows in from the main gate.", startMinute: 9 * 60 + 30),
            Stop(dayIndex: 2, name: "Museo Nacional de Bellas Artes", address: "Av. del Libertador 1473", latitude: -34.5837, longitude: -58.3927, category: .sight, notes: "Free entry; closed Mondays.", startMinute: 11 * 60),
            Stop(dayIndex: 2, name: "Floralis Genérica", address: "Av. Figueroa Alcorta 2301", latitude: -34.5836, longitude: -58.3947, category: .sight, notes: "Opens its petals in the morning.", startMinute: 13 * 60),
            Stop(dayIndex: 2, name: "MALBA", address: "Av. Figueroa Alcorta 3415", latitude: -34.5770, longitude: -58.4033, category: .sight, notes: "Latin American art; café on the ground floor.", startMinute: 14 * 60 + 30),
            Stop(dayIndex: 2, name: "Don Julio Parrilla", address: "Guatemala 4691, Palermo", latitude: -34.5885, longitude: -58.4300, category: .food, notes: "Join the waitlist on their site in the morning.", startMinute: 20 * 60),

            // Day 4 — Tigre day trip.
            Stop(dayIndex: 3, name: "Estación Retiro", address: "Av. Ramos Mejía 1430", latitude: -34.5910, longitude: -58.3745, category: .transport, notes: "Mitre line to Tigre, ~50 min. Load the SUBE card first.", startMinute: 8 * 60 + 30),
            Stop(dayIndex: 3, name: "Puerto de Frutos", address: "Tigre", latitude: -34.4175, longitude: -58.5733, category: .shopping, notes: "Wicker, mate gourds and cheap leather.", startMinute: 10 * 60 + 30),
            Stop(dayIndex: 3, name: "Delta boat tour", address: "Estación Fluvial, Tigre", latitude: -34.4262, longitude: -58.5797, category: .activity, notes: "One-hour lancha through the islands.", startMinute: 13 * 60),
            Stop(dayIndex: 3, name: "Museo de Arte de Tigre", address: "Paseo Victorica 972", latitude: -34.4180, longitude: -58.5733, category: .sight, notes: "On the riverfront walk back to the station.", startMinute: 16 * 60),

            // Day 5 — Palermo, Corrientes and tango.
            Stop(dayIndex: 4, name: "Plaza Serrano", address: "Palermo Soho", latitude: -34.5875, longitude: -58.4305, category: .activity, notes: "Best on a weekend afternoon.", startMinute: 11 * 60),
            Stop(dayIndex: 4, name: "Jardín Botánico Carlos Thays", address: "Av. Santa Fe 3951", latitude: -34.5780, longitude: -58.4188, category: .sight, notes: "Shady and free; cats everywhere.", startMinute: 12 * 60 + 30),
            Stop(dayIndex: 4, name: "El Ateneo Grand Splendid", address: "Av. Santa Fe 1860", latitude: -34.5963, longitude: -58.3943, category: .sight, notes: "Books in the old theatre; café on stage.", startMinute: 15 * 60),
            Stop(dayIndex: 4, name: "Obelisco", address: "Av. 9 de Julio y Corrientes", latitude: -34.6037, longitude: -58.3816, category: .sight, notes: "Photos from the north side get both lanes of 9 de Julio.", startMinute: 17 * 60),
            Stop(dayIndex: 4, name: "Café de los Angelitos", address: "Av. Rivadavia 2100", latitude: -34.6095, longitude: -58.3960, category: .activity, notes: "Dinner and tango show — book ahead, arrive 20:00.", startMinute: 20 * 60),

            // Day 6 — fly north to Iguazú.
            Stop(dayIndex: 5, name: "Aeroparque Jorge Newbery", address: "Av. Costanera Rafael Obligado", latitude: -34.5592, longitude: -58.4156, category: .transport, notes: "Domestic only; be there 90 minutes before.", startMinute: 6 * 60 + 30),
            Stop(dayIndex: 5, name: "Hito Tres Fronteras", address: "Puerto Iguazú, Misiones", latitude: -25.5972, longitude: -54.5797, category: .sight, notes: "Sunset over the meeting of three countries.", startMinute: 18 * 60),

            // Day 7 — the falls.
            Stop(dayIndex: 6, name: "Parque Nacional Iguazú", address: "Ruta 101 km 142, Puerto Iguazú", latitude: -25.6969, longitude: -54.4383, category: .sight, notes: "Buy the ticket online; take the Ecological Train first.", startMinute: 8 * 60),
            Stop(dayIndex: 6, name: "Garganta del Diablo", address: "Upper Circuit, Parque Nacional Iguazú", latitude: -25.6953, longitude: -54.4367, category: .sight, notes: "You will get soaked — bag the phone.", startMinute: 9 * 60 + 30),
            Stop(dayIndex: 6, name: "Sendero Macuco", address: "Parque Nacional Iguazú", latitude: -25.6900, longitude: -54.4400, category: .activity, notes: "7 km round trip through the jungle to a waterfall.", startMinute: 13 * 60)
        ],
        bookings: [
            Booking(
                type: "flight",
                title: "AEP → IGR",
                provider: "Aerolíneas Argentinas",
                confirmation: "AR1740",
                dayIndex: 5,
                startMinute: 8 * 60 + 20,
                durationMinutes: 105,
                startLocation: "Aeroparque Jorge Newbery (AEP)",
                endLocation: "Puerto Iguazú (IGR)",
                cost: 148,
                currency: "USD",
                metadata: ["flight_number": "AR1740"]
            ),
            Booking(
                type: "lodging",
                title: "Palermo loft",
                provider: "Palermo Soho",
                confirmation: "WR-4821",
                dayIndex: 0,
                startMinute: 15 * 60,
                durationMinutes: 60 * 24 * 5,
                startLocation: "Palermo Soho",
                endLocation: "Buenos Aires",
                cost: 640,
                currency: "USD",
                metadata: nil
            ),
            Booking(
                type: "lodging",
                title: "Iguazú riverside lodge",
                provider: "Puerto Iguazú",
                confirmation: "WR-4822",
                dayIndex: 5,
                startMinute: 14 * 60,
                durationMinutes: 60 * 24 * 2,
                startLocation: "Puerto Iguazú",
                endLocation: "Misiones",
                cost: 210,
                currency: "USD",
                metadata: nil
            )
        ]
    )

    /// Adds the sample content once. Safe to call on every open: it returns
    /// immediately when the trip already has places.
    static func seedIfNeeded(trip: Trip, api: WandererAPI) async {
        guard isSample(trip), // guest trips fall back to Trip.samples
              let plan = plan(for: trip) else { return }
        guard let existing = try? await api.places(tripID: trip.id),
              existing.isEmpty,
              let days = try? await api.days(tripID: trip.id),
              !days.isEmpty else { return }

        let start = TripDayRecord.date(from: trip.startDate) ?? Date()

        for (index, stop) in plan.stops.enumerated() {
            guard days.indices.contains(stop.dayIndex) else { continue }
            let dayID = days[stop.dayIndex].id.uuidString.lowercased()
            let body: [String: JSONValue] = [
                "day_id": .string(dayID),
                "name": .string(stop.name),
                "address": .string(stop.address),
                "lat": .number(stop.latitude),
                "lng": .number(stop.longitude),
                "category": .string(stop.category.rawValue),
                "notes": .optional(stop.notes),
                "position": .integer(index),
                "start_time": .optional(timeLabel(stop.startMinute))
            ]
            _ = try? await api.addPlace(tripID: trip.id, body: body)
        }

        for booking in plan.bookings {
            let day = Calendar.current.date(byAdding: .day, value: booking.dayIndex, to: start) ?? start
            let begin = day.addingTimeInterval(TimeInterval(booking.startMinute * 60))
            let end = begin.addingTimeInterval(TimeInterval(booking.durationMinutes * 60))
            var body: [String: JSONValue] = [
                "type": .string(booking.type),
                "title": .string(booking.title),
                "provider": .optional(booking.provider),
                "confirmation_code": .optional(booking.confirmation),
                "start_at": .string(ISO8601DateFormatter().string(from: begin)),
                "end_at": .string(ISO8601DateFormatter().string(from: end)),
                "start_location": .optional(booking.startLocation),
                "end_location": .optional(booking.endLocation),
                "cost": .optional(booking.cost),
                "currency": .optional(booking.currency)
            ]
            if let metadata = booking.metadata {
                body["metadata"] = .object(metadata.mapValues { .string($0) })
            }
            _ = try? await api.addReservation(tripID: trip.id, body: body)
        }

        // One stop already visited, so the journal and progress have something
        // to show on the sample instead of an empty first-run.
        if let first = try? await api.places(tripID: trip.id), let place = first.first {
            _ = try? await api.setPlaceVisited(
                tripID: trip.id,
                placeID: place.id,
                visitedAt: ISO8601DateFormatter().string(from: Date())
            )
        }
    }

    private static func timeLabel(_ minute: Int?) -> String? {
        guard let minute else { return nil }
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
