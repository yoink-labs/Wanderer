import Foundation
import Supabase

@MainActor
final class AttachmentsStore: ObservableObject {
    @Published private(set) var attachments: [AttachmentRecord] = []
    @Published private(set) var signedURLs: [UUID: URL] = [:]
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let bucket = "trip-attachments"

    init(client: SupabaseClient = WandererSupabase.client) {
        self.client = client
    }

    func load(tripID: UUID) async {
        guard WandererSupabase.client.auth.currentSession != nil else { return }
        do {
            attachments = try await client.from("attachments")
                .select()
                .eq("trip_id", value: tripID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            for attachment in attachments {
                await makeSignedURL(for: attachment)
            }
        } catch {
            errorMessage = "Couldn't load attachments: \(error.localizedDescription)"
        }
    }

    func upload(tripID: UUID, data: Data, fileName: String, mimeType: String) async {
        isUploading = true
        defer { isUploading = false }

        do {
            let session = try await client.auth.session
            let safeName = fileName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
            let path = "\(tripID.uuidString)/\(UUID().uuidString)-\(safeName)"

            try await client.storage
                .from(bucket)
                .upload(path, data: data, options: FileOptions(contentType: mimeType))

            let payload = NewAttachmentPayload(
                tripId: tripID.uuidString,
                name: fileName,
                storagePath: path,
                mimeType: mimeType,
                sizeBytes: data.count,
                createdBy: session.user.id.uuidString
            )
            try await client.from("attachments").insert(payload).execute()
            await load(tripID: tripID)
        } catch {
            errorMessage = "Couldn't upload that file: \(error.localizedDescription)"
        }
    }

    func delete(_ attachment: AttachmentRecord) async {
        do {
            try await client.storage.from(bucket).remove(paths: [attachment.storagePath])
            try await client.from("attachments")
                .delete()
                .eq("id", value: attachment.id.uuidString)
                .execute()
            attachments.removeAll { $0.id == attachment.id }
            signedURLs[attachment.id] = nil
        } catch {
            errorMessage = "Couldn't remove that attachment: \(error.localizedDescription)"
        }
    }

    private func makeSignedURL(for attachment: AttachmentRecord) async {
        do {
            let url = try await client.storage
                .from(bucket)
                .createSignedURL(path: attachment.storagePath, expiresIn: 3600)
            signedURLs[attachment.id] = url
        } catch {
            // A missing URL only disables opening that row; the list still works.
        }
    }
}

private struct NewAttachmentPayload: Encodable {
    let tripId: String
    let name: String
    let storagePath: String
    let mimeType: String
    let sizeBytes: Int
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case name
        case storagePath = "storage_path"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case createdBy = "created_by"
    }
}
