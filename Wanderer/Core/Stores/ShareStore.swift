import Foundation

@MainActor
final class ShareStore: ObservableObject {
    @Published private(set) var members: [TripMemberRecord] = []
    @Published private(set) var invites: [TripInviteRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Whether the last invite was actually emailed by the Worker, so the
    /// caller can fall back to the Mail sheet when Resend is unconfigured.
    private(set) var lastInviteWasEmailed = false

    private var api: WandererAPI? { CloudSession.shared.api }

    func load(tripID: UUID) async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await api.members(tripID: tripID).map {
                TripMemberRecord(tripId: tripID, userId: $0.userId, role: $0.role)
            }
            invites = try await api.invites(tripID: tripID)
        } catch {
            errorMessage = "Couldn't load the people on this trip: \(error.localizedDescription)"
        }
    }

    /// The Worker sends the invite email as part of creating it.
    func sendInviteEmail(trip: Trip, to: String, inviterName: String) async -> Bool {
        lastInviteWasEmailed
    }

    func invite(tripID: UUID, email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains("."), let api else { return false }

        do {
            let result = try await api.createInvite(tripID: tripID, email: trimmed)
            lastInviteWasEmailed = result.emailed
            await load(tripID: tripID)
            return true
        } catch {
            errorMessage = "Couldn't save that invite: \(error.localizedDescription)"
            return false
        }
    }
}
