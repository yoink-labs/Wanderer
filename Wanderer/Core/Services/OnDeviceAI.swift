import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A day plan the on-device model proposed. Every stop names a place that was
/// already in the trip or passed in as a candidate, so the model can reorder
/// and schedule but never invent a venue.
struct AIPlanStop: Identifiable, Hashable {
    let id = UUID()
    let name: String
    /// "09:30" — 24-hour local time on the day being planned.
    let startTime: String
    let minutes: Int
    let why: String
}

struct AIPlan: Hashable {
    let theme: String
    let stops: [AIPlanStop]
}

/// Apple's on-device model (Apple Intelligence). iOS 26+ only, and only on
/// devices with the model available — everything here degrades to a plain
/// explanation and the manual planner stays fully usable.
enum OnDeviceAI {
    enum Availability: Equatable {
        case ready
        case unsupported(String)

        var isReady: Bool { self == .ready }
    }

    static var availability: Availability {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                return .unsupported("This iPhone doesn't support Apple Intelligence, so on-device planning is unavailable.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unsupported("Turn on Apple Intelligence in Settings to use on-device planning.")
            case .unavailable(.modelNotReady):
                return .unsupported("The on-device model is still getting ready. Try again in a minute.")
            @unknown default:
                return .unsupported("On-device planning isn't available on this device right now.")
            }
        }
#endif
        return .unsupported("On-device planning needs iOS 26 and Apple Intelligence.")
    }

    /// Reorders and schedules the places already in the trip (the day's stops
    /// plus anything unscheduled) into a readable day.
    static func planDay(
        destination: String,
        dayLabel: String,
        existing: [String],
        ideas: [String],
        preference: String
    ) async throws -> AIPlan {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await planDayModern(
                destination: destination,
                dayLabel: dayLabel,
                existing: existing,
                ideas: ideas,
                preference: preference
            )
        }
#endif
        throw AIError.unavailable
    }

    /// A packing list for the trip. No places involved, so it is safe to let
    /// the model write freely.
    static func packingList(destination: String, days: Int, month: String, notes: String) async throws -> [String] {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await packingListModern(destination: destination, days: days, month: month, notes: notes)
        }
#endif
        throw AIError.unavailable
    }

    enum AIError: LocalizedError {
        case unavailable
        case empty
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "On-device AI isn't available right now."
            case .empty:
                return "The model didn't return a plan. Try again with fewer notes."
            case .failed(let message):
                return message
            }
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedStop {
    @Guide(description: "The exact name of one of the places listed in the request")
    var name: String
    @Guide(description: "Start time in 24-hour HH:mm, between 08:00 and 21:00")
    var startTime: String
    @Guide(description: "Minutes to spend there", .range(20...180))
    var minutes: Int
    @Guide(description: "One short sentence on why this stop fits the day")
    var why: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedDayPlan {
    @Guide(description: "A short theme for the day, at most six words")
    var theme: String
    @Guide(description: "Stops in the order they should be visited", .maximumCount(8))
    var stops: [GeneratedStop]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPackingList {
    @Guide(description: "Packing items, each at most four words", .maximumCount(18))
    var items: [String]
}

@available(iOS 26.0, *)
extension OnDeviceAI {
    static func planDayModern(
        destination: String,
        dayLabel: String,
        existing: [String],
        ideas: [String],
        preference: String
    ) async throws -> AIPlan {
        guard availability.isReady else { throw AIError.unavailable }
        guard !existing.isEmpty || !ideas.isEmpty else { throw AIError.empty }

        let candidates = (existing + ideas).joined(separator: "; ")
        let prompt = """
        Plan \(dayLabel) in \(destination).
        Places already on the day: \(existing.isEmpty ? "none" : existing.joined(separator: "; ")).
        Other places saved for this trip: \(ideas.isEmpty ? "none" : ideas.joined(separator: "; ")).
        Preferred pace or interests: \(preference.isEmpty ? "balanced, one good meal, not rushed" : preference).

        Use only these places: \(candidates).
        Order them into a realistic day, allowing travel time between stops. \
        Do not invent places, opening hours, prices or addresses.
        """

        let session = LanguageModelSession(
            instructions: """
            You are a trip planner that arranges places the traveller already chose. \
            Never add a place that is not in the supplied list. Keep the day to at most 7 stops.
            """
        )

        do {
            let response = try await session.respond(to: prompt, generating: GeneratedDayPlan.self)
            let plan = response.content
            let stops = plan.stops.map {
                AIPlanStop(name: $0.name, startTime: $0.startTime, minutes: $0.minutes, why: $0.why)
            }
            guard !stops.isEmpty else { throw AIError.empty }
            return AIPlan(theme: plan.theme, stops: stops)
        } catch let error as LanguageModelSession.GenerationError {
            throw AIError.failed(error.localizedDescription)
        }
    }

    static func packingListModern(destination: String, days: Int, month: String, notes: String) async throws -> [String] {
        guard availability.isReady else { throw AIError.unavailable }
        let session = LanguageModelSession(
            instructions: "You write short, practical packing lists. No commentary."
        )
        let prompt = """
        Packing list for \(days) days in \(destination) in \(month).
        Personal notes: \(notes.isEmpty ? "none" : notes).
        """
        let response = try await session.respond(to: prompt, generating: GeneratedPackingList.self)
        return response.content.items
    }
}
#endif
