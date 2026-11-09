import SwiftUI

struct Trip: Identifiable, Hashable {
    let id: UUID
    var title: String
    var destination: String
    var dateRange: String
    var days: Int
    var places: Int
    var members: [String]
    var palette: TripPalette
    var symbol: String
    var startDate: String?
    var endDate: String?
    var coverUrl: String?
    var notes: String?
    var timezone: String

    init(
        id: UUID = UUID(),
        title: String,
        destination: String,
        dateRange: String,
        days: Int,
        places: Int,
        members: [String],
        palette: TripPalette,
        symbol: String,
        startDate: String? = nil,
        endDate: String? = nil,
        coverUrl: String? = nil,
        notes: String? = nil,
        timezone: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.dateRange = dateRange
        self.days = days
        self.places = places
        self.members = members
        self.palette = palette
        self.symbol = symbol
        self.startDate = startDate
        self.endDate = endDate
        self.coverUrl = coverUrl
        self.notes = notes
        self.timezone = timezone
    }

    static let samples: [Trip] = [
        Trip(
            title: "Kyoto in autumn",
            destination: "Kyoto, Japan",
            dateRange: "Nov 12 – 17",
            days: 5,
            places: 14,
            members: ["AR", "MK"],
            palette: .kyoto,
            symbol: "leaf.fill"
        ),
        Trip(
            title: "Barcelona long weekend",
            destination: "Barcelona, Spain",
            dateRange: "Dec 4 – 8",
            days: 4,
            places: 11,
            members: ["AR", "JL", "SK"],
            palette: .barcelona,
            symbol: "sun.max.fill"
        ),
        Trip(
            title: "Lisbon with friends",
            destination: "Lisbon, Portugal",
            dateRange: "Mar 14 – 20",
            days: 6,
            places: 18,
            members: ["AR", "JL"],
            palette: .lisbon,
            symbol: "tram.fill"
        ),
        Trip(
            title: "Reykjavík road trip",
            destination: "Reykjavík, Iceland",
            dateRange: "Jun 2 – 9",
            days: 7,
            places: 22,
            members: ["AR", "MK", "SK"],
            palette: .reykjavik,
            symbol: "mountain.2.fill"
        )
    ]
}

enum TripPhase {
    case upcoming
    case inProgress
    case past
}

extension Trip {
    var phase: TripPhase {
        let today = Calendar.current.startOfDay(for: Date())
        guard let start = TripDayRecord.date(from: startDate),
              let end = TripDayRecord.date(from: endDate) else {
            return .upcoming
        }
        if today < Calendar.current.startOfDay(for: start) { return .upcoming }
        return today <= Calendar.current.startOfDay(for: end) ? .inProgress : .past
    }
}

enum TripPalette: String, Hashable, CaseIterable {
    case kyoto
    case barcelona
    case lisbon
    case reykjavik
    case lagoon

    var colors: [Color] {
        switch self {
        case .kyoto:
            return [Color(hex: 0xD77A61), Color(hex: 0xB65E48), Color(hex: 0x223843)]
        case .barcelona:
            return [Color(hex: 0xD8B4A0), Color(hex: 0xD77A61), Color(hex: 0x8C4F3F)]
        case .lisbon:
            return [Color(hex: 0x3C5A66), Color(hex: 0x223843), Color(hex: 0x16232B)]
        case .reykjavik:
            return [Color(hex: 0x6B8589), Color(hex: 0x3C5A66), Color(hex: 0x223843)]
        case .lagoon:
            return [Color(hex: 0xDF9581), Color(hex: 0xD77A61), Color(hex: 0xB65E48)]
        }
    }
}
