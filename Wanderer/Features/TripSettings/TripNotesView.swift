import SwiftUI

struct TripNotesView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TripsStore()
    @State private var text: String
    @State private var savedText: String
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var confirmDiscard = false
    @FocusState private var isEditing: Bool

    init(trip: Trip) {
        self.trip = trip
        _text = State(initialValue: trip.notes ?? "")
        _savedText = State(initialValue: trip.notes ?? "")
    }

    private var hasChanges: Bool {
        text != savedText
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.ligga(.body))
                    .foregroundStyle(WandererTheme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isEditing)
                    .padding(12)
                    .accessibilityLabel("Trip notes")

                if text.isEmpty {
                    Text("Flight numbers, local tips, addresses, reminders…")
                        .font(.ligga(.body))
                        .foregroundStyle(WandererTheme.muted)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liggaCard()
            .padding(.horizontal, TripToolsLayout.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges || isSaving)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .task {
                if store.trips.isEmpty {
                    await store.load()
                }
                // Only adopt the fresh copy if the user hasn't started typing.
                if let record = store.trips.first(where: { $0.id == trip.id }), !hasChanges {
                    text = record.notes ?? ""
                    savedText = text
                }
            }
        }
        .tint(WandererTheme.charcoal)
    }

    private func save() {
        isSaving = true
        Task {
            await store.updateNotes(trip, notes: text)
            isSaving = false
            if store.errorMessage == nil {
                savedText = text
                dismiss()
            } else {
                errorText = store.errorMessage
            }
        }
    }
}

#Preview {
    TripNotesView(trip: Trip.samples[0])
}
