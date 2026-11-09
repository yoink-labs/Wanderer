import PhotosUI
import SwiftUI

struct TripSettingsView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TripsStore()

    @State private var title: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var showDeleteConfirmation = false
    @State private var errorText: String?
    @State private var coverItem: PhotosPickerItem?
    @State private var coverURL: String?
    @State private var isUpdatingCover = false

    init(trip: Trip) {
        self.trip = trip
        _title = State(initialValue: trip.title)
        _destination = State(initialValue: trip.destination)
        _startDate = State(initialValue: Self.date(from: trip.startDate) ?? Date())
        _endDate = State(initialValue: Self.date(from: trip.endDate) ?? Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date())
        _coverURL = State(initialValue: trip.coverUrl)
    }

    private var dayCount: Int {
        max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        endDate >= startDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    coverCard

                    card {
                        field("Trip name", icon: "textformat", text: $title)
                        Divider().overlay(WandererTheme.line)
                        field("Destination", icon: "mappin.and.ellipse", text: $destination)
                    }

                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Dates", systemImage: "calendar")
                                .font(.ligga(.subheadline, weight: .semibold))
                                .foregroundStyle(WandererTheme.muted)

                            HStack(spacing: 12) {
                                dateField("Start", date: $startDate)
                                dateField("End", date: $endDate)
                            }

                            if endDate < startDate {
                                Label("End date is before the start date.", systemImage: "exclamationmark.circle")
                                    .font(.ligga(.footnote, weight: .medium))
                                    .foregroundStyle(WandererTheme.coralDeep)
                            } else {
                                Text(dayCount == 1 ? "1 day" : "\(dayCount) days")
                                    .font(.ligga(.footnote, weight: .medium))
                                    .foregroundStyle(WandererTheme.muted)
                            }
                        }
                    }

                    TripToolPrimaryButton(title: "Save changes", isEnabled: canSave && !store.isLoading) {
                        save()
                    }
                    .padding(.top, 4)

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete trip")
                            .font(.ligga(.headline, weight: .semibold))
                            .foregroundStyle(WandererTheme.coralDeep)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.horizontal, TripToolsLayout.gutter)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave || store.isLoading)
                }
            }
            .alert("Delete this trip?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        await store.delete(trip)
                        if store.errorMessage == nil {
                            NotificationCenter.default.post(name: .tripDeleted, object: trip.id)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the itinerary, places, bookings, expenses and checklist for this trip.")
            }
            .task {
                if store.trips.isEmpty {
                    await store.load()
                }
                if let record = store.trips.first(where: { $0.id == trip.id }) {
                    title = record.title
                    destination = record.destination ?? ""
                    startDate = Self.date(from: record.startDate) ?? startDate
                    endDate = Self.date(from: record.endDate) ?? endDate
                }
            }
            .onChange(of: store.errorMessage) { _, message in
                if let message { errorText = message }
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

    private func save() {
        guard canSave else { return }
        Task {
            await store.update(
                trip,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: startDate,
                endDate: endDate
            )
            if store.errorMessage == nil {
                NotificationCenter.default.post(name: .tripsChanged, object: nil)
                dismiss()
            }
        }
    }

    private var coverURLValue: URL? {
        if let coverURL, let url = URL(string: coverURL) { return url }
        return ImageCatalog.cover(for: trip.destination)
    }

    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let url = coverURLValue {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            LinearGradient(
                                colors: [WandererTheme.desert, WandererTheme.peach],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .frame(height: 170)
                    .clipped()
                }

                LinearGradient(
                    colors: [.clear, WandererTheme.charcoal.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                PhotosPicker(selection: $coverItem, matching: .images) {
                    Label("Change cover", systemImage: "photo")
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(WandererTheme.charcoal.opacity(0.82), in: Capsule())
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cover photo")
            .overlay {
                if isUpdatingCover {
                    ProgressView()
                        .tint(.white)
                        .padding(12)
                        .background(WandererTheme.charcoal.opacity(0.5), in: Circle())
                }
            }

        }
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                isUpdatingCover = true
                let updated = await store.updateCover(trip, imageData: data)
                isUpdatingCover = false
                if let updated {
                    coverURL = updated
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liggaCard()
    }

    private func field(_ label: String, icon: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
                TextField(label, text: text)
                    .font(.ligga(.body, weight: .medium))
                    .foregroundStyle(WandererTheme.ink)
            }
        }
        .frame(minHeight: 44)
    }

    private func dateField(_ label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
            DatePicker(label, selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(WandererTheme.charcoal)
        }
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

extension Notification.Name {
    static let tripsChanged = Notification.Name("wanderer.tripsChanged")
    static let tripDeleted = Notification.Name("wanderer.tripDeleted")
}

#Preview {
    TripSettingsView(trip: Trip.samples[0])
}
