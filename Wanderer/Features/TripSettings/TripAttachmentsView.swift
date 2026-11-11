import PhotosUI
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct TripAttachmentsView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var store = AttachmentsStore()
    @State private var showImporter = false
    @State private var errorText: String?
    @State private var didLoad = false
    @State private var pendingDelete: AttachmentRecord?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var previewURL: URL?
    @AppStorage("wanderer.isGuest") private var isGuest = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !didLoad {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if store.attachments.isEmpty {
                        TripToolEmptyState(
                            icon: "doc.on.doc",
                            title: "No files yet",
                            message: "Keep booking PDFs, tickets and confirmation screenshots with the trip.",
                            actionTitle: "Add a file"
                        ) {
                            showImporter = true
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.attachments) { attachment in
                                tile(attachment)
                            }
                        }
                    }

                    if didLoad {
                        Label(
                            isGuest ? "Saved on this phone. Sign in to share files with your trip." : "Private to trip members",
                            systemImage: isGuest ? "iphone" : "lock"
                        )
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, TripToolsLayout.gutter)
                .padding(.vertical, 12)
            }
            .background(WandererTheme.platinum.ignoresSafeArea())
            .quickLookPreview($previewURL)
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await uploadPhoto(item) }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showPhotos = true
                        } label: {
                            Label("From Photos", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("From Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add file")
                    .accessibilityIdentifier("attachments-add")
                    .disabled(store.isUploading)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .image, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await upload(url) }
                    }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .task {
                await store.load(tripID: trip.id)
                didLoad = true
            }
            .overlay {
                if store.isUploading {
                    ProgressView("Uploading…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .onChange(of: store.errorMessage) { _, message in
                if let message {
                    errorText = message
                    store.errorMessage = nil
                }
            }
            .confirmationDialog(
                "Delete this file?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { attachment in
                Button("Delete", role: .destructive) {
                    Task { await store.delete(attachment) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { attachment in
                Text("\(attachment.name) will be removed for everyone on this trip.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .tint(WandererTheme.controlTint)
    }

    // MARK: - Tiles

    private func tile(_ attachment: AttachmentRecord) -> some View {
        let url = store.signedURLs[attachment.id]
        return Button {
            open(attachment, url: url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                FileThumbnail(url: url, glyph: glyph(for: attachment), isImage: attachment.icon == "photo")
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text(kindLabel(for: attachment))
                            .font(.ligga(.caption2, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0x10283A).opacity(0.85), in: Capsule())
                            .padding(8)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .lineLimit(2, reservesSpace: true)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                    Text(attachment.sizeLabel)
                        .font(.ligga(.caption))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.muted)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .liggaCard()
            .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.liggaPressable)
        .disabled(url == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(attachment.name), \(metaLine(for: attachment))")
        .accessibilityHint(url == nil ? "Not available right now" : "Opens the file")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Delete") { pendingDelete = attachment }
        .contextMenu {
            if let url {
                Button {
                    open(attachment, url: url)
                } label: {
                    Label("Open", systemImage: "eye")
                }
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                pendingDelete = attachment
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Device files open in Quick Look in place; account files open their
    /// short-lived signed link.
    private func open(_ attachment: AttachmentRecord, url: URL?) {
        guard let url else { return }
        LiggaHaptics.tap()
        if url.isFileURL {
            previewURL = url
        } else {
            openURL(url)
        }
    }

    private func kindLabel(for attachment: AttachmentRecord) -> String {
        let ext = (attachment.name as NSString).pathExtension.uppercased()
        if !ext.isEmpty, ext.count <= 4 { return ext }
        return attachment.icon == "photo" ? "Photo" : "File"
    }

    private func glyph(for attachment: AttachmentRecord) -> String {
        switch attachment.icon {
        case "paperclip": return "doc.text"
        default: return attachment.icon
        }
    }

    private func metaLine(for attachment: AttachmentRecord) -> String {
        let ext = (attachment.name as NSString).pathExtension.uppercased()
        return [ext.isEmpty ? nil : ext, attachment.sizeLabel.isEmpty ? nil : attachment.sizeLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorText = "That photo couldn't be read. Try another one."
            return
        }
        let type = item.supportedContentTypes.first ?? .jpeg
        let ext = type.preferredFilenameExtension ?? "jpg"
        let stamp = Date().formatted(.dateTime.year().month().day().hour().minute())
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        await store.upload(
            tripID: trip.id,
            data: data,
            fileName: "Photo \(stamp).\(ext)",
            mimeType: type.preferredMIMEType ?? "image/jpeg"
        )
    }

    private func upload(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            await store.upload(
                tripID: trip.id,
                data: data,
                fileName: url.lastPathComponent,
                mimeType: mime
            )
        } catch {
            errorText = "Couldn't read that file: \(error.localizedDescription)"
        }
    }
}

#Preview {
    TripAttachmentsView(trip: Trip.samples[0])
}

/// Thumbnail for a file tile: Quick Look for files on the device, the image
/// itself for remote photos, and a large glyph otherwise.
private struct FileThumbnail: View {
    let url: URL?
    let glyph: String
    let isImage: Bool

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            WandererTheme.fillMuted
            if let image {
                // Documents read from the top, so crop from there.
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .clipped()
                }
            } else if let url, !url.isFileURL, isImage {
                AsyncImage(url: url) { phase in
                    if let loaded = phase.image {
                        loaded.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url, url.isFileURL else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 360, height: 360),
                scale: displayScale,
                representationTypes: .thumbnail
            )
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        }
    }

    private var placeholder: some View {
        Image(systemName: glyph)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(WandererTheme.muted)
    }
}
