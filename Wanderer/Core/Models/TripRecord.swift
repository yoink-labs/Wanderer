import Foundation

/// Row shape returned by PostgREST for `public.trips`.
struct TripRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let ownerId: UUID
    var title: String
    var destination: String?
    var startDate: String?
    var endDate: String?
    var currency: String
    var coverUrl: String?
    var coverColor: String?
    var notes: String?
    var timezone: String
    var placeCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case title
        case destination
        case startDate = "start_date"
        case endDate = "end_date"
        case currency
        case coverUrl = "cover_url"
        case coverColor = "cover_color"
        case notes
        case timezone
        case placeCount = "place_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        title = try container.decode(String.self, forKey: .title)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        coverColor = try container.decodeIfPresent(String.self, forKey: .coverColor)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? TimeZone.current.identifier
        // The Worker returns the count inline; older rows may omit it.
        placeCount = try container.decodeIfPresent(Int.self, forKey: .placeCount) ?? 0
    }

    var dayCount: Int {
        guard let start = Self.date(from: startDate), let end = Self.date(from: endDate) else {
            return 0
        }
        let difference = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, difference + 1)
    }

    var dateRangeLabel: String {
        guard let start = Self.date(from: startDate), let end = Self.date(from: endDate) else {
            return "Dates not set"
        }
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "MMM d"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
            ? "d"
            : "MMM d"
        return "\(startFormatter.string(from: start)) – \(endFormatter.string(from: end))"
    }

    func asTrip(memberInitials: [String]) -> Trip {
        Trip(
            id: id,
            title: title,
            destination: destination ?? "Somewhere new",
            dateRange: dateRangeLabel,
            days: dayCount,
            places: placeCount,
            members: memberInitials.isEmpty ? ["LG"] : memberInitials,
            palette: TripPalette.allCases.absolutelyStable(seed: id.uuidString),
            symbol: "airplane",
            startDate: startDate,
            endDate: endDate,
            coverUrl: coverUrl,
            notes: notes,
            timezone: timezone
        )
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private extension Array where Element == TripPalette {
    func absolutelyStable(seed: String) -> TripPalette {
        let value = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return self[abs(value) % count]
    }
}
