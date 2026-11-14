import SwiftUI

struct DayNoteView: View {
    let day: TripDayRecord
    @ObservedObject var store: TripDetailStore

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorText: String?

    init(note: String, day: TripDayRecord, store: TripDetailStore) {
        self.day = day
        self.store = store
        _text = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label(day.fullDateLabel, systemImage: "calendar")
                    Text("·")
                    Text("Day \(day.dayIndex + 1)")
                }
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
                .padding(.horizontal, WandererTheme.screenPadding)
                .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.ligga(.body))
                    .foregroundStyle(WandererTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 240)
                    .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WandererTheme.line, lineWidth: 1)
                    )
                    .padding(.horizontal, WandererTheme.screenPadding)

                Spacer(minLength: 0)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Day note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.updateDayNotes(day, notes: text)
                            if store.errorMessage == nil {
                                dismiss()
                            } else {
                                errorText = store.errorMessage
                            }
                        }
                    }
                    .fontWeight(.bold)
                }
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
