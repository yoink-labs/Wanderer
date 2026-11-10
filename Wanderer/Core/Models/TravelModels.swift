import Foundation

// MARK: - Trip days

struct TripDayRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    let dayIndex: Int
    let date: String?
    var title: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case dayIndex = "day_index"
        case date
        case title
        case notes
    }

    var weekdayLabel: String {
        guard let date = Self.date(from: date) else { return "Day \(dayIndex + 1)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var shortDateLabel: String {
        guard let date = Self.date(from: date) else { return "Day \(dayIndex + 1)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    var fullDateLabel: String {
        guard let date = Self.date(from: date) else { return "Day \(dayIndex + 1)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

// MARK: - Places

enum PlaceCategory: String, Codable, CaseIterable, Identifiable {
    case sight
    case food
    case lodging
    case activity
    case transport
    case shopping
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sight: return "Sight"
        case .food: return "Food"
        case .lodging: return "Stay"
        case .activity: return "Activity"
        case .transport: return "Transport"
        case .shopping: return "Shopping"
        case .note: return "Note"
        }
    }

    var icon: String {
        switch self {
        case .sight: return "building.columns.fill"
        case .food: return "fork.knife"
        case .lodging: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .transport: return "tram.fill"
        case .shopping: return "bag.fill"
        case .note: return "note.text"
        }
    }
}

struct PlaceRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    var dayId: UUID?
    var name: String
    var address: String?
    var lat: Double?
    var lng: Double?
    var category: PlaceCategory
    var notes: String?
    var website: String?
    var phone: String?
    var priceLevel: Int?
    var rating: Double?
    var photoUrl: String?
    var startTime: String?
    var endTime: String?
    var position: Int
    var visitedAt: String?
    var createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case dayId = "day_id"
        case name
        case address
        case lat
        case lng
        case category
        case notes
        case website
        case phone
        case priceLevel = "price_level"
        case rating
        case photoUrl = "photo_url"
        case startTime = "start_time"
        case endTime = "end_time"
        case position
        case visitedAt = "visited_at"
        case createdBy = "created_by"
    }

    func timeLabel(in timeZoneIdentifier: String? = nil) -> String? {
        guard let startTime, !startTime.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: startTime) ?? ISO8601DateFormatter().date(from: startTime)
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let timeZoneIdentifier, let zone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = zone
        }
        return formatter.string(from: date)
    }

    var coordinate: Coordinate? {
        guard let lat, let lng else { return nil }
        return Coordinate(latitude: lat, longitude: lng)
    }

    var isVisited: Bool { visitedAt != nil }
}

struct Coordinate: Hashable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Reservations

enum ReservationType: String, Codable, CaseIterable, Identifiable {
    case flight
    case lodging
    case car
    case restaurant
    case train
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: return "Flight"
        case .lodging: return "Stay"
        case .car: return "Car"
        case .restaurant: return "Restaurant"
        case .train: return "Train"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .lodging: return "bed.double.fill"
        case .car: return "car.fill"
        case .restaurant: return "fork.knife"
        case .train: return "tram.fill"
        case .other: return "ticket.fill"
        }
    }
}

struct ReservationRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    var type: ReservationType
    var title: String
    var provider: String?
    var confirmationCode: String?
    var startAt: String?
    var endAt: String?
    var startLocation: String?
    var endLocation: String?
    var cost: Double?
    var currency: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case type
        case title
        case provider
        case confirmationCode = "confirmation_code"
        case startAt = "start_at"
        case endAt = "end_at"
        case startLocation = "start_location"
        case endLocation = "end_location"
        case cost
        case currency
        case notes
    }

    func dateLabel(in timeZoneIdentifier: String? = nil) -> String? {
        guard let parsedStart else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        if let timeZoneIdentifier, let zone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = zone
        }
        return formatter.string(from: parsedStart)
    }

    var parsedStart: Date? {
        Self.date(from: startAt)
    }

    var parsedEnd: Date? {
        Self.date(from: endAt)
    }

    func timeLabel(in timeZoneIdentifier: String? = nil) -> String? {
        guard let parsedStart else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let timeZoneIdentifier, let zone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = zone
        }
        return formatter.string(from: parsedStart)
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

// MARK: - Expenses

enum ExpenseSplitMode: String, Codable, CaseIterable, Identifiable {
    case equal
    case exact
    case percent
    case shares

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: return "Equally"
        case .exact: return "Exact amounts"
        case .percent: return "Percentages"
        case .shares: return "Shares"
        }
    }

    var icon: String {
        switch self {
        case .equal: return "equal.circle.fill"
        case .exact: return "number.circle.fill"
        case .percent: return "percent"
        case .shares: return "chart.pie.fill"
        }
    }
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case lodging
    case transport
    case activities
    case shopping
    case other

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .lodging: return "bed.double.fill"
        case .transport: return "car.fill"
        case .activities: return "figure.walk"
        case .shopping: return "bag.fill"
        case .other: return "creditcard.fill"
        }
    }
}

struct ExpenseRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    var title: String
    var amount: Double
    var currency: String
    var category: ExpenseCategory
    var paidBy: UUID?
    var splitWith: [UUID]
    var splitMode: ExpenseSplitMode
    var spentAt: String
    var notes: String?
    var placeId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case title
        case amount
        case currency
        case category
        case paidBy = "paid_by"
        case splitWith = "split_with"
        case splitMode = "split_mode"
        case spentAt = "spent_at"
        case notes
        case placeId = "place_id"
    }
}

struct ExpenseSplitRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    let expenseId: UUID
    let userId: UUID
    var amount: Double
    var weight: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case expenseId = "expense_id"
        case userId = "user_id"
        case amount
        case weight
    }
}

struct SettlementRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    let fromUser: UUID
    let toUser: UUID
    let amount: Double
    let currency: String
    let settledAt: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case fromUser = "from_user"
        case toUser = "to_user"
        case amount
        case currency
        case settledAt = "settled_at"
        case note
    }
}

struct MemberBalance: Identifiable, Hashable {
    let member: TripMemberProfile
    let net: Double

    var id: UUID { member.userId }
    var isOwed: Bool { net > 0.005 }
    var owes: Bool { net < -0.005 }
}

struct MemberProfile: Codable, Hashable {
    let id: UUID
    let displayName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
    }
}

struct TripMemberProfile: Codable, Identifiable, Hashable {
    let userId: UUID
    let role: TripRole
    let profiles: MemberProfile?

    var id: UUID { userId }

    var displayName: String {
        if let name = profiles?.displayName, !name.isEmpty { return name }
        if let email = profiles?.email, !email.isEmpty { return email }
        return "Trip member"
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "TM" : String(letters).uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
        case profiles
    }
}

// MARK: - Checklist

struct ChecklistRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    var title: String
    var isChecked: Bool
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case title
        case isChecked = "is_checked"
        case position
    }
}

// MARK: - Profile

struct ProfileRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var email: String?
    var displayName: String?
    var avatarUrl: String?
    var locale: String
    var currency: String
    var units: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case locale
        case currency
        case units
    }
}

// MARK: - Guides

struct GuideRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var authorId: UUID?
    var title: String
    var summary: String?
    var destination: String?
    var coverUrl: String?
    var isPublished: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case title
        case summary
        case destination
        case coverUrl = "cover_url"
        case isPublished = "is_published"
    }
}

struct GuidePlaceRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let guideId: UUID
    var name: String
    var address: String?
    var lat: Double?
    var lng: Double?
    var notes: String?
    var photoUrl: String?
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case guideId = "guide_id"
        case name
        case address
        case lat
        case lng
        case notes
        case photoUrl = "photo_url"
        case position
    }
}

// MARK: - Trip members

enum TripRole: String, Codable, CaseIterable {
    case owner
    case editor
    case viewer

    var title: String {
        switch self {
        case .owner: return "Owner"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }
}

struct TripMemberRecord: Codable, Identifiable, Hashable {
    let tripId: UUID
    let userId: UUID
    let role: TripRole

    var id: String { "\(tripId.uuidString)-\(userId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case userId = "user_id"
        case role
    }
}

struct TripInviteRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    let email: String
    let role: TripRole
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case email
        case role
        case acceptedAt = "accepted_at"
    }
}

// MARK: - Attachments

struct AttachmentRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    var reservationId: UUID?
    var placeId: UUID?
    var name: String
    var storagePath: String
    var mimeType: String?
    var sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case reservationId = "reservation_id"
        case placeId = "place_id"
        case name
        case storagePath = "storage_path"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
    }

    var sizeLabel: String {
        guard let sizeBytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    var icon: String {
        let lower = (mimeType ?? name).lowercased()
        if lower.contains("pdf") { return "doc.richtext" }
        if lower.contains("image") || lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "photo" }
        return "paperclip"
    }
}

// MARK: - Visited places

struct VisitedPlaceRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var countryCode: String
    var city: String?
    var year: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case countryCode = "country_code"
        case city
        case year
    }
}
