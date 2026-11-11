import Foundation

/// Most-recently-opened trip IDs, persisted as a comma-separated string so it
/// can live in `@AppStorage`. The first ID is the last trip the user opened.
enum RecentTrips {
    static let storageKey = "wanderer.recentTripIDs"
    static let limit = 8

    static func decode(_ raw: String) -> [UUID] {
        raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    static func recording(_ id: UUID, in raw: String) -> String {
        var ids = decode(raw)
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        return ids.prefix(limit).map(\.uuidString).joined(separator: ",")
    }

    static func removing(_ id: UUID, from raw: String) -> String {
        decode(raw).filter { $0 != id }.map(\.uuidString).joined(separator: ",")
    }
}

/// Decides which trip Home features and how the rest are ordered.
///
/// Featured, in priority order: a trip in progress (most recently opened
/// first), the last opened trip that isn't over, the soonest upcoming trip,
/// then the newest trip. The list puts recently opened trips first, keeps the
/// store's order for the rest, and sinks past trips to the bottom.
struct HomeTripOrdering {
    enum Reason: Equatable {
        case inProgress
        case recent
        case upNext(daysAway: Int?)
        case latest
    }

    let featured: Trip?
    let reason: Reason
    let others: [Trip]

    init(trips: [Trip], recentIDs: [UUID], now: Date = Date()) {
        let recencyRank = Dictionary(
            recentIDs.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        func rank(_ trip: Trip) -> Int { recencyRank[trip.id] ?? Int.max }

        let byRecency = trips.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element), right = rank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)

        var featured: Trip?
        var reason: Reason = .latest

        if let live = byRecency.first(where: { $0.phase == .inProgress }) {
            featured = live
            reason = .inProgress
        } else if let recent = byRecency.first(where: { recencyRank[$0.id] != nil && $0.phase != .past }) {
            featured = recent
            reason = .recent
        } else if let next = trips
            .filter({ $0.phase == .upcoming })
            .compactMap({ trip in Self.startDate(of: trip).map { (trip, $0) } })
            .min(by: { $0.1 < $1.1 }) {
            featured = next.0
            reason = .upNext(daysAway: Self.days(from: now, to: next.1))
        } else if let first = trips.first {
            featured = first
            reason = .latest
        }

        self.featured = featured
        self.reason = reason

        let remaining = byRecency.filter { $0.id != featured?.id }
        let current = remaining.filter { $0.phase != .past }
        let past = remaining.filter { $0.phase == .past }
        self.others = current + past
    }

    var overline: String {
        switch reason {
        case .inProgress:
            return "Happening now"
        case .recent:
            return "Jump back in"
        case .upNext(let days):
            guard let days else { return "Up next" }
            switch days {
            case ..<1: return "Starts today"
            case 1: return "Starts tomorrow"
            default: return "Starts in \(days) days"
            }
        case .latest:
            return featured?.phase == .past ? "Latest trip" : "Up next"
        }
    }

    private static func startDate(of trip: Trip) -> Date? {
        TripDayRecord.date(from: trip.startDate)
    }

    private static func days(from now: Date, to date: Date) -> Int? {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day
    }
}

/// One row in Home's combined search results.
enum HomeSearchResult: Identifiable {
    case trip(Trip)
    case guide(GuideRecord)

    var id: String {
        switch self {
        case .trip(let trip): return "trip-\(trip.id.uuidString)"
        case .guide(let guide): return "guide-\(guide.id.uuidString)"
        }
    }
}

/// Token-based, case- and accent-insensitive matching over trips and guides.
/// "reykjavik" finds "Reykjavík"; "kyoto autumn" needs both words somewhere
/// in the title, destination or summary. Title-prefix hits rank first.
enum HomeSearch {
    static func tokens(for query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func trips(_ trips: [Trip], matching query: String) -> [Trip] {
        rank(trips, query: query, title: \.title) { [$0.title, $0.destination] }
    }

    static func guides(_ guides: [GuideRecord], matching query: String) -> [GuideRecord] {
        rank(guides, query: query, title: \.title) { [$0.title, $0.destination ?? "", $0.summary ?? ""] }
    }

    private static func rank<T>(
        _ items: [T],
        query: String,
        title: KeyPath<T, String>,
        fields: (T) -> [String]
    ) -> [T] {
        let words = tokens(for: query)
        guard !words.isEmpty else { return items }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        let hits = items.enumerated().filter { _, item in
            let haystack = fields(item).joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: options) != nil }
        }

        return hits.sorted { lhs, rhs in
            let left = isPrefix(lhs.element[keyPath: title], words[0], options)
            let right = isPrefix(rhs.element[keyPath: title], words[0], options)
            return left == right ? lhs.offset < rhs.offset : left
        }.map(\.element)
    }

    private static func isPrefix(_ text: String, _ word: String, _ options: String.CompareOptions) -> Bool {
        text.range(of: word, options: options.union(.anchored)) != nil
    }
}

extension Int {
    /// "1 day", "3 days".
    func liggaCounted(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))"
    }
}

/// Where today sits on a trip's run of days, for the route spine on the
/// featured postcard. `current` is nil before the trip starts and after it
/// ends; `completed` counts days already behind you.
struct TripRouteProgress: Equatable {
    let dayCount: Int
    let completed: Int
    let current: Int?

    /// Spines longer than this are drawn as a continuous bar instead of beads.
    static let beadLimit = 14

    init(trip: Trip, now: Date = Date(), calendar: Calendar = .current) {
        let count = max(1, trip.days)
        dayCount = count
        guard let start = TripDayRecord.date(from: trip.startDate) else {
            completed = 0
            current = nil
            return
        }
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: today).day ?? 0
        if offset < 0 {
            completed = 0
            current = nil
        } else if offset >= count {
            completed = count
            current = nil
        } else {
            completed = offset
            current = offset
        }
    }

    var showsBeads: Bool { dayCount <= Self.beadLimit }

    /// "Day 3 of 5", "5 days" or "Done".
    var label: String {
        if let current { return "Day \(current + 1) of \(dayCount)" }
        if completed >= dayCount { return "\(dayCount) days, done" }
        return dayCount == 1 ? "1 day" : "\(dayCount) days"
    }
}
