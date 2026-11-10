import Foundation
import Supabase

@MainActor
final class ShareStore: ObservableObject {
    @Published private(set) var members: [TripMemberRecord] = []
    @Published private(set) var invites: [TripInviteRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    /// Whether the last cloud invite was actually emailed, so the caller can
    /// fall back to the Mail sheet when Resend is not configured.
    private(set) var lastInviteWasEmailed = false

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

    private var cloud: WandererAPI? {
        BackendMode.current == .cloud ? CloudSession.shared.api : nil
    }

    func load(tripID: UUID) async {
        if let cloud {
            isLoading = true
            defer { isLoading = false }
            do {
                members = try await cloud.members(tripID: tripID).map {
                    TripMemberRecord(tripId: tripID, userId: $0.userId, role: $0.role)
                }
                invites = try await cloud.invites(tripID: tripID)
            } catch {
                errorMessage = "Couldn't load the people on this trip: \(error.localizedDescription)"
            }
            return
        }

        guard WandererSupabase.client.auth.currentSession != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await client.from("trip_members")
                .select()
                .eq("trip_id", value: tripID.uuidString)
                .execute()
                .value

            invites = try await client.from("trip_invites")
                .select()
                .eq("trip_id", value: tripID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't load the people on this trip: \(error.localizedDescription)"
        }
    }

    func sendInviteEmail(trip: Trip, to: String, inviterName: String) async -> Bool {
        if cloud != nil {
            // The Worker sends the email as part of creating the invite.
            return lastInviteWasEmailed
        }

        do {
            let session = try await client.auth.session
            let endpoint = SupabaseConfig.url.appendingPathComponent("functions/v1/send-trip-invite")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")

            let payload = InviteEmailPayload(
                to: to,
                tripTitle: trip.title,
                inviterName: inviterName,
                link: "https://wanderer.app/trip/\(trip.id.uuidString)"
            )
            request.httpBody = try JSONEncoder().encode(payload)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func invite(tripID: UUID, email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else { return false }

        if let cloud {
            do {
                let result = try await cloud.createInvite(tripID: tripID, email: trimmed)
                lastInviteWasEmailed = result.emailed
                await load(tripID: tripID)
                return true
            } catch {
                errorMessage = "Couldn't save that invite: \(error.localizedDescription)"
                return false
            }
        }

        do {
            let payload = NewInvitePayload(tripId: tripID.uuidString, email: trimmed, role: TripRole.editor.rawValue)
            try await client.from("trip_invites").insert(payload).execute()
            await load(tripID: tripID)
            return true
        } catch {
            errorMessage = "Couldn't save that invite: \(error.localizedDescription)"
            return false
        }
    }
}

private struct InviteEmailPayload: Encodable {
    let to: String
    let tripTitle: String
    let inviterName: String
    let link: String

    enum CodingKeys: String, CodingKey {
        case to
        case tripTitle = "tripTitle"
        case inviterName = "inviterName"
        case link
    }
}

private struct NewInvitePayload: Encodable {
    let tripId: String
    let email: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case email
        case role
    }
}
