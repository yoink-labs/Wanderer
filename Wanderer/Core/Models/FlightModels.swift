import Foundation

// MARK: - Live flight status

struct FlightAirline: Decodable, Equatable {
    let name: String?
    let iata: String?
}

struct FlightEnd: Decodable, Equatable {
    let airport: String?
    let airportName: String?
    let city: String?
    let terminal: String?
    let gate: String?
    let scheduled: String?
    let estimated: String?
    let actual: String?
    let delayMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case airport
        case airportName = "airport_name"
        case city
        case terminal
        case gate
        case scheduled
        case estimated
        case actual
        case delayMinutes = "delay_minutes"
    }

    var delay: Int? {
        if let delayMinutes, delayMinutes != 0 { return delayMinutes }
        return nil
    }
}

struct FlightStatusRecord: Decodable, Equatable, Identifiable {
    let flightNumber: String
    let date: String
    let status: String
    let statusLabel: String
    let airline: FlightAirline?
    let aircraft: String?
    let departure: FlightEnd
    let arrival: FlightEnd
    let greatCircleKm: Double?
    let updatedAt: String?
    let attribution: String

    var id: String { "\(flightNumber):\(date)" }

    enum CodingKeys: String, CodingKey {
        case flightNumber = "flight_number"
        case date
        case status
        case statusLabel = "status_label"
        case airline
        case aircraft
        case departure
        case arrival
        case greatCircleKm = "great_circle_km"
        case updatedAt = "updated_at"
        case attribution
    }

    /// Statuses that mean "nothing more will change".
    var isFinished: Bool {
        ["Arrived", "Canceled", "Diverted", "CanceledUncertain"].contains(status)
    }

    var isTrouble: Bool {
        ["Delayed", "Canceled", "CanceledUncertain", "Diverted", "GateClosed"].contains(status)
    }
}

struct FlightLookupEnvelope: Decodable, Equatable {
    let flight: FlightStatusRecord?
    let cached: Bool
    let stale: Bool
    let fetchedAt: String?
    let attribution: String
    let budgetExhausted: Bool

    enum CodingKeys: String, CodingKey {
        case flight
        case cached
        case stale
        case fetchedAt = "fetched_at"
        case attribution
        case budgetExhausted = "budget_exhausted"
    }
}

struct FlightBudget: Decodable, Equatable {
    let unitsUsed: Int
    let requestsUsed: Int
    let unitsCap: Int
    let requestsCap: Int

    enum CodingKeys: String, CodingKey {
        case unitsUsed = "units_used"
        case requestsUsed = "requests_used"
        case unitsCap = "units_cap"
        case requestsCap = "requests_cap"
    }
}

struct TripFlightsEnvelope: Decodable {
    let flights: [String: FlightLookupEnvelope]
    let refreshed: Int
    let attribution: String
    let budget: FlightBudget
}

// MARK: - Personal layer (only you see it)

struct PersonalOverrideRecord: Decodable, Identifiable {
    let itemType: String
    let itemId: String
    let hidden: Bool
    let data: [String: JSONValue]

    var id: String { "\(itemType):\(itemId)" }

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case hidden
        case data
    }
}

struct PersonalLayerRecord: Decodable {
    let overrides: [PersonalOverrideRecord]
    let privatePlaces: [PlaceRecord]
    let privateReservations: [ReservationRecord]

    enum CodingKeys: String, CodingKey {
        case overrides
        case privatePlaces = "private_places"
        case privateReservations = "private_reservations"
    }

    static let empty = PersonalLayerRecord(overrides: [], privatePlaces: [], privateReservations: [])
}
