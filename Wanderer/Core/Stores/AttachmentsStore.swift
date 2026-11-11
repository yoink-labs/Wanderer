import Foundation

@MainActor
final class AttachmentsStore: ObservableObject {
    @Published private(set) var attachments: [AttachmentRecord] = []
    @Published private(set) var signedURLs: [UUID: URL] = [:]
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private var api: WandererAPI? { CloudSession.shared.api }

    func load(tripID: UUID) async {
        guard let api else { return }
        do {
            attachments = try await api.attachments(tripID: tripID)
            for attachment in attachments {
                if let url = try? await api.attachmentURL(tripID: tripID, attachmentID: attachment.id) {
                    signedURLs[attachment.id] = url
                }
            }
        } catch {
            errorMessage = "Couldn't load attachments: \(error.localizedDescription)"
        }
    }

    func upload(tripID: UUID, data: Data, fileName: String, mimeType: String) async {
        guard let api else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            _ = try await api.uploadAttachment(
                tripID: tripID,
                data: data,
                fileName: fileName,
                mimeType: mimeType
            )
            await load(tripID: tripID)
        } catch {
            errorMessage = "Couldn't upload that file: \(error.localizedDescription)"
        }
    }

    func delete(_ attachment: AttachmentRecord) async {
        guard let api else { return }
        do {
            try await api.deleteAttachment(tripID: attachment.tripId, attachmentID: attachment.id)
            attachments.removeAll { $0.id == attachment.id }
            signedURLs[attachment.id] = nil
        } catch {
            errorMessage = "Couldn't remove that attachment: \(error.localizedDescription)"
        }
    }
}
