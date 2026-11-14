import Foundation
import UIKit

/// Free exports that match what paid planners charge for: a calendar file and
/// a Google Maps driving/walking route, both built from the trip the user
/// already has. Nothing leaves the device.
enum TripExports {

    // MARK: - Google Maps

    /// Google Maps directions links for a day, chunked because the free URL
    /// scheme accepts at most nine waypoints (eleven stops) per link.
    static func googleMapsURLs(places: [PlaceRecord], travelMode: String = "walking") -> [URL] {
        let coordinates = places.compactMap(\.coordinate)
        guard coordinates.count >= 2 else { return [] }

        var urls: [URL] = []
        var index = 0
        while index < coordinates.count - 1 {
            let chunk = Array(coordinates[index..<min(index + 10, coordinates.count)])
            guard chunk.count >= 2 else { break }
            let origin = chunk.first!
            let destination = chunk.last!
            let waypoints = chunk.dropFirst().dropLast()

            var components = URLComponents(string: "https://www.google.com/maps/dir/")!
            var items = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "travelmode", value: travelMode),
                URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
                URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            ]
            if !waypoints.isEmpty {
                items.append(URLQueryItem(
                    name: "waypoints",
                    value: waypoints.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
                ))
            }
            components.queryItems = items
            if let url = components.url { urls.append(url) }
            index += 9
        }
        return urls
    }

    // MARK: - Calendar

    /// One `.ics` file with timed stops, bookings and all-day place events.
    static func writeCalendarFile(
        trip: Trip,
        days: [TripDayRecord],
        places: [PlaceRecord],
        reservations: [ReservationRecord]
    ) -> URL? {
        let calendar = ics(trip: trip, days: days, places: places, reservations: reservations)
        guard !calendar.isEmpty else { return nil }
        let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = title.isEmpty ? "Trip" : title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).ics")
        do {
            try calendar.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func ics(
        trip: Trip,
        days: [TripDayRecord],
        places: [PlaceRecord],
        reservations: [ReservationRecord]
    ) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Wanderer//Trip//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escape(trip.title))",
        ]

        let dayByID = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0) })
        let stamp = utcStamp(Date())

        for reservation in reservations {
            guard let start = reservation.parsedStart else { continue }
            let end = reservation.parsedEnd ?? start.addingTimeInterval(2 * 3600)
            lines.append("BEGIN:VEVENT")
            lines.append("UID:reservation-\(reservation.id.uuidString.lowercased())@wanderer")
            lines.append("DTSTAMP:\(stamp)")
            lines.append("DTSTART:\(utcStamp(start))")
            lines.append("DTEND:\(utcStamp(end))")
            lines.append("SUMMARY:\(escape("\(reservation.type.title): \(reservation.title)"))")
            if let location = reservation.startLocation ?? reservation.endLocation {
                lines.append("LOCATION:\(escape(location))")
            }
            var description = [reservation.provider, reservation.confirmationCode, reservation.notes]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if description.isEmpty { description = "Added in Wanderer" }
            lines.append("DESCRIPTION:\(escape(description))")
            lines.append("END:VEVENT")
        }

        for place in places {
            if let start = isoDate(place.startTime) {
                let end = isoDate(place.endTime) ?? start.addingTimeInterval(3600)
                lines.append("BEGIN:VEVENT")
                lines.append("UID:place-\(place.id.uuidString.lowercased())@wanderer")
                lines.append("DTSTAMP:\(stamp)")
                lines.append("DTSTART:\(utcStamp(start))")
                lines.append("DTEND:\(utcStamp(end))")
                lines.append("SUMMARY:\(escape(place.name))")
                if let address = place.address { lines.append("LOCATION:\(escape(address))") }
                var description = [place.category.title, place.notes]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if description.isEmpty { description = "Planned in Wanderer" }
                lines.append("DESCRIPTION:\(escape(description))")
                lines.append("END:VEVENT")
            } else if let day = place.dayId.flatMap({ dayByID[$0] }), let date = TripDayRecord.date(from: day.date) {
                lines.append("BEGIN:VEVENT")
                lines.append("UID:place-\(place.id.uuidString.lowercased())@wanderer")
                lines.append("DTSTAMP:\(stamp)")
                lines.append("DTSTART;VALUE=DATE:\(dateStamp(date))")
                lines.append("DTEND;VALUE=DATE:\(dateStamp(date.addingTimeInterval(86400)))")
                lines.append("SUMMARY:\(escape(place.name))")
                if let address = place.address { lines.append("LOCATION:\(escape(address))") }
                if let notes = place.notes { lines.append("DESCRIPTION:\(escape(notes))") }
                lines.append("END:VEVENT")
            }
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func isoDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    /// RFC 5545 text escaping: backslash, semicolon, comma and newlines.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}
