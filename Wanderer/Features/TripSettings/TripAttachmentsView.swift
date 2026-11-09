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

    var body: some View {
        NavigationStack {
            List {
                if !didLoad {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .tripToolListRow()
                } else if store.attachments.isEmpty {
                    TripToolEmptyState(
                        icon: "paperclip",
                        title: "No files yet",
                        message: "Add booking PDFs, tickets or confirmation screenshots.",
                        actionTitle: "Add a file"
                    ) {
                        showImporter = true
                    }
                    .tripToolListRow()
                } else {
                    ForEach(store.attachments) { attachment in
                        attachmentRow(attachment)
                    }
                }

                if didLoad {
                    Label("Private to trip members", systemImage: "lock")
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .tripToolListRow()
                }
            }
            .tripToolList()
            .navigationTitle("Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add file")
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
        .tint(WandererTheme.charcoal)
    }

    // MARK: - Rows

    private func attachmentRow(_ attachment: AttachmentRecord) -> some View {
        let url = store.signedURLs[attachment.id]

        return Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: glyph(for: attachment))
                    .font(.ligga(.body, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(metaLine(for: attachment))
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if url == nil {
                    Text("Unavailable")
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.ligga(.caption, weight: .semibold))
                        .foregroundStyle(WandererTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .liggaCard()
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel("\(attachment.name), \(metaLine(for: attachment))")
        .accessibilityHint("Opens the file")
        .tripToolListRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = attachment
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(WandererTheme.coralDeep)
        }
        .contextMenu {
            if let url {
                Button {
                    openURL(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
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
