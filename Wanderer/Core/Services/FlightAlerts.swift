import Foundation
import UserNotifications

/// Local flight alerts. There is no server push in this build, so a change is
/// detected when the app refreshes a tracked flight (opening a trip, the
/// planner's ten-minute poll, or pull-to-refresh) and delivered as a local
/// notification. The first observation of a flight is never announced.
enum FlightAlerts {
    static let enabledKey = "wanderer.flightAlerts"
    private static let seenKey = "wanderer.flightAlerts.seen"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Compares the latest statuses with the last ones this device saw, sends
    /// one notification per meaningful change, then remembers the new state.
    static func process(tripTitle: String, statuses: [String: FlightLookupEnvelope]) {
        guard isEnabled else { return }
        var seen = loadSeen()
        var notifications: [(String, String)] = []

        for envelope in statuses.values {
            guard let flight = envelope.flight else { continue }
            let key = "\(flight.flightNumber):\(flight.date)"
            let signature = [
                flight.status,
                flight.departure.gate ?? "",
                flight.departure.terminal ?? "",
                String(flight.departure.delay ?? 0),
            ].joined(separator: "|")

            if let previous = seen[key], previous != signature {
                if let body = message(previous: previous, flight: flight, tripTitle: tripTitle) {
                    notifications.append(("Flight \(flight.flightNumber)", body))
                }
            }
            seen[key] = signature
        }

        saveSeen(seen)
        for (title, body) in notifications {
            deliver(title: title, body: body)
        }
    }

    private static func message(previous: String, flight: FlightStatusRecord, tripTitle: String) -> String? {
        let parts = previous.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let oldStatus = parts.indices.contains(0) ? parts[0] : ""
        let oldGate = parts.indices.contains(1) ? parts[1] : ""
        let oldTerminal = parts.indices.contains(2) ? parts[2] : ""
        let oldDelay = parts.indices.contains(3) ? Int(parts[3]) ?? 0 : 0

        if flight.status == "Canceled", oldStatus != "Canceled" {
            return "Your flight \(flight.flightNumber) has been cancelled. Check with your airline."
        }
        if let gate = flight.departure.gate, !gate.isEmpty, gate != oldGate, !oldGate.isEmpty {
            return "The gate for \(flight.flightNumber) has changed to \(gate). Check with your airline."
        }
        if let terminal = flight.departure.terminal, !terminal.isEmpty, terminal != oldTerminal, !oldTerminal.isEmpty {
            return "The terminal for \(flight.flightNumber) has changed to \(terminal). Check with your airline."
        }
        if let delay = flight.departure.delay, delay > 0, delay != oldDelay {
            return "Your flight \(flight.flightNumber) is delayed by \(delay) minutes. Check with your airline."
        }
        if flight.status != oldStatus {
            return "\(flight.flightNumber) is now \(flight.statusLabel.lowercased())."
        }
        return nil
    }

    private static func deliver(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "flight-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private static func loadSeen() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: seenKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveSeen(_ seen: [String: String]) {
        guard let data = try? JSONEncoder().encode(seen) else { return }
        UserDefaults.standard.set(data, forKey: seenKey)
    }
}
