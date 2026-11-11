import SwiftUI

struct Trip: Identifiable, Hashable, Codable {
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
    var shareToken: String? = nil

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
        timezone: String = TimeZone.current.identifier,
        shareToken: String? = nil
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
        self.shareToken = shareToken
    }

    /// First-run guest samples, dated relative to today so Home always shows
    /// one trip underway and the rest coming up.
    static var samples: [Trip] {
        [
            sample("Kyoto in autumn", "Kyoto, Japan", startOffset: -2, days: 5, places: 14,
                   members: ["AR", "MK"], palette: .kyoto, symbol: "leaf.fill", timezone: "Asia/Tokyo"),
            sample("Barcelona long weekend", "Barcelona, Spain", startOffset: 24, days: 4, places: 11,
                   members: ["AR", "JL", "SK"], palette: .barcelona, symbol: "sun.max.fill", timezone: "Europe/Madrid"),
            sample("Lisbon with friends", "Lisbon, Portugal", startOffset: 61, days: 6, places: 18,
                   members: ["AR", "JL"], palette: .lisbon, symbol: "tram.fill", timezone: "Europe/Lisbon"),
            sample("Reykjavík road trip", "Reykjavík, Iceland", startOffset: 140, days: 7, places: 22,
                   members: ["AR", "MK", "SK"], palette: .reykjavik, symbol: "mountain.2.fill", timezone: "Atlantic/Reykjavik")
        ]
    }

    static func sample(
        _ title: String, _ destination: String, startOffset: Int, days: Int, places: Int,
        members: [String], palette: TripPalette, symbol: String, timezone: String, now: Date = Date()
    ) -> Trip {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: startOffset, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
        // Stable ids keep "recently opened" working across launches.
        // (`hashValue` is seeded per launch, so use a fixed FNV-1a hash.)
        let hash = title.unicodeScalars.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1.value)) &* 0x100000001b3 }
        let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", hash & 0xFFFFFFFFFFFF)) ?? UUID()
        return Trip(
            id: id, title: title, destination: destination,
            dateRange: Self.rangeLabel(start, end), days: days, places: places,
            members: members, palette: palette, symbol: symbol,
            startDate: Self.isoDay(start), endDate: Self.isoDay(end), timezone: timezone
        )
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func rangeLabel(_ start: Date, _ end: Date) -> String {
        let sameMonth = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
        let startText = start.formatted(.dateTime.month(.abbreviated).day())
        let endText = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText) – \(endText)"
    }
}

enum TripPhase {
    case upcoming
    case inProgress
    case past
}

extension Trip {
    var phase: TripPhase { phase(on: Date()) }

    /// Phase relative to a given day, so ordering and tests don't depend on
    /// the wall clock.
    func phase(on now: Date) -> TripPhase {
        let today = Calendar.current.startOfDay(for: now)
        guard let start = TripDayRecord.date(from: startDate),
              let end = TripDayRecord.date(from: endDate) else {
            return .upcoming
        }
        if today < Calendar.current.startOfDay(for: start) { return .upcoming }
        return today <= Calendar.current.startOfDay(for: end) ? .inProgress : .past
    }
}

enum TripPalette: String, Hashable, CaseIterable, Codable {
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
