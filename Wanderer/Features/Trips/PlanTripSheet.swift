import SwiftUI

struct PlanTripSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var destination = ""
    @State private var tripTitle = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
    @State private var travelers = 2

    let onCreate: (NewTripDraft) -> Void

    private var dayCount: Int {
        max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
    }

    private var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    private var canCreate: Bool {
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where to?")
                            .font(.ligga(.title2, weight: .bold))
                            .foregroundStyle(WandererTheme.ink)
                        Text("Start with a destination. You can add days, places and reservations next.")
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                    }

                    fieldCard {
                        labeledField("Destination", systemImage: "mappin.and.ellipse", placeholder: "Kyoto, Japan", text: $destination)
                        Divider().overlay(WandererTheme.line)
                        labeledField("Trip name (optional)", systemImage: "textformat", placeholder: "Kyoto in autumn", text: $tripTitle)
                    }

                    fieldCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Dates", systemImage: "calendar")
                                .font(.ligga(.subheadline, weight: .semibold))
                                .foregroundStyle(WandererTheme.muted)

                            HStack(spacing: 12) {
                                datePicker("Start", date: $startDate)
                                datePicker("End", date: $endDate)
                            }

                            Text("\(dayCount) days · \(dateRange)")
                                .font(.ligga(.caption, weight: .medium))
                                .foregroundStyle(WandererTheme.coralDeep)
                        }
                    }

                    fieldCard {
                        HStack {
                            Label("Travelers", systemImage: "person.2.fill")
                                .font(.ligga(.subheadline, weight: .semibold))
                                .foregroundStyle(WandererTheme.muted)
                            Spacer()
                            Stepper(value: $travelers, in: 1...12) {
                                Text("\(travelers)")
                                    .font(.ligga(.headline, weight: .bold))
                                    .foregroundStyle(WandererTheme.ink)
                                    .frame(minWidth: 24)
                            }
                            .labelsHidden()
                        }
                    }
                }
                .padding(WandererTheme.screenPadding)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .fontWeight(.bold)
                        .disabled(!canCreate)
                }
            }
        }
    }

    private func create() {
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = tripTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let draft = NewTripDraft(
            title: title.isEmpty ? "\(destination) trip" : title,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            days: dayCount,
            dateRange: dateRange,
            coverColor: ["E95C45", "3E7CB8", "2F8E88", "6E4A7E"].randomElement() ?? "E95C45",
            timezone: TimeZone.current.identifier
        )

        onCreate(draft)
        dismiss()
    }

    private func fieldCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func labeledField(_ label: String, systemImage: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WandererTheme.coral)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
                TextField(placeholder, text: text)
                    .font(.ligga(.body, weight: .medium))
                    .foregroundStyle(WandererTheme.ink)
            }
        }
    }

    private func datePicker(_ label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
            DatePicker("", selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }
}

#Preview {
    PlanTripSheet { _ in }
}
