import Foundation
import SwiftUI
import UIKit

struct ReservationsView: View {
    @ObservedObject var store: TripDetailStore
    @AppStorage("wanderer.currency") private var defaultCurrency = "USD"

    @State private var showAdd = false
    @State private var filter: ReservationType?
    @State private var pendingDelete: ReservationRecord?

    /// Filter chips only earn their space once the list gets long.
    private static let filterThreshold = 6

    var body: some View {
        List {
            if store.reservations.isEmpty {
                TripToolEmptyState(
                    icon: "ticket",
                    title: "No bookings yet",
                    message: "Keep flights, stays, cars and tables in one place, sorted by day.",
                    actionTitle: "Add booking"
                ) {
                    showAdd = true
                }
                .tripToolListRow()
                .accessibilityIdentifier("reservations-empty-add")
            } else {
                if showsFilter {
                    filterRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if sections.isEmpty {
                    Text("No \(filter?.title.lowercased() ?? "") bookings.")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .tripToolListRow()
                }

                ForEach(sections) { section in
                    TripToolGroupLabel(title: section.title, trailing: section.items.count > 1 ? "\(section.items.count)" : nil)
                        .tripToolListRow()

                    ForEach(section.items) { reservation in
                        row(for: reservation)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = reservation
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(WandererTheme.coralDeep)
                            }
                            .contextMenu {
                                if let code = reservation.confirmationCode?.tripToolsNilIfEmpty {
                                    Button {
                                        UIPasteboard.general.string = code
                                    } label: {
                                        Label("Copy confirmation", systemImage: "doc.on.doc")
                                    }
                                }
                                Button(role: .destructive) {
                                    pendingDelete = reservation
                                } label: {
                                    Label("Delete booking", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .tripToolList()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.reservations.isEmpty {
                TripToolBottomBar {
                    TripToolPrimaryButton(title: "Add booking", icon: "plus") {
                        showAdd = true
                    }
                    .accessibilityIdentifier("reservations-add")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddReservationSheet(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this booking?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { reservation in
            Button("Delete", role: .destructive) {
                Task { await store.deleteReservation(reservation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { reservation in
            Text(reservation.title)
        }
        .onChange(of: store.reservations.count) { _, _ in
            if let filter, !availableTypes.contains(filter) {
                self.filter = nil
            }
        }
    }

    // MARK: - Filter

    private var showsFilter: Bool {
        store.reservations.count > Self.filterThreshold && availableTypes.count > 1
    }

    private var availableTypes: [ReservationType] {
        let present = Set(store.reservations.map(\.type))
        return ReservationType.allCases.filter { present.contains($0) }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TripToolFilterChip(title: "All", isSelected: filter == nil) {
                    filter = nil
                }
                ForEach(availableTypes) { type in
                    TripToolFilterChip(
                        title: "\(type.title) · \(store.reservations.filter { $0.type == type }.count)",
                        icon: type.icon,
                        isSelected: filter == type
                    ) {
                        filter = filter == type ? nil : type
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: - Grouping

    private var sections: [ReservationSection] {
        let visible = store.reservations.filter { filter == nil || $0.type == filter }
        let sorted = visible.sorted { lhs, rhs in
            let left = TripToolsFormat.date(fromISO: lhs.startAt)
            let right = TripToolsFormat.date(fromISO: rhs.startAt)
            switch (left, right) {
            case let (leftDate?, rightDate?):
                return leftDate < rightDate
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        var result: [ReservationSection] = []
        for reservation in sorted {
            let date = TripToolsFormat.date(fromISO: reservation.startAt)
            let id = date.map { dayKey($0) } ?? "undated"
            let title = date.map { dayHeader($0) } ?? "No date yet"
            if let index = result.firstIndex(where: { $0.id == id }) {
                result[index].items.append(reservation)
            } else {
                result.append(ReservationSection(id: id, title: title, items: [reservation]))
            }
        }
        return result
    }

    private var tripTimeZone: TimeZone {
        TimeZone(identifier: store.trip.timezone) ?? .current
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(format)
        formatter.timeZone = tripTimeZone
        return formatter
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = tripTimeZone
        return formatter.string(from: date)
    }

    private func dayHeader(_ date: Date) -> String {
        formatter("EEEMMMd").string(from: date)
    }

    // MARK: - Rows

    private func row(for reservation: ReservationRecord) -> some View {
        BookingTicket(reservation: reservation, timeZone: tripTimeZone, currency: defaultCurrency)
            .accessibilityLabel(accessibilityLabel(for: reservation))
            .tripToolListRow()
    }

    private func accessibilityLabel(for reservation: ReservationRecord) -> String {
        var parts = [reservation.type.title, reservation.title]
        if let detail = detailLine(for: reservation) { parts.append(detail) }
        if let time = timeLine(for: reservation) { parts.append(time) }
        if let route = routeLine(for: reservation) { parts.append(route) }
        if let cost = reservation.cost {
            parts.append(TripToolsFormat.money(cost, code: reservation.currency ?? defaultCurrency))
        }
        return parts.joined(separator: ", ")
    }

    private func detailLine(for reservation: ReservationRecord) -> String? {
        var parts: [String] = []
        if let provider = reservation.provider?.tripToolsTrimmed, !provider.isEmpty {
            parts.append(provider)
        }
        if let code = reservation.confirmationCode?.tripToolsTrimmed, !code.isEmpty {
            parts.append(code)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func timeLine(for reservation: ReservationRecord) -> String? {
        guard let start = reservation.parsedStart else { return nil }
        let time = formatter("jmm")
        let startText = time.string(from: start)
        guard let end = reservation.parsedEnd, end > start else { return startText }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tripTimeZone
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(startText) → \(time.string(from: end))"
        }
        return "\(startText) → \(formatter("EEEMMMdjmm").string(from: end))"
    }

    private func routeLine(for reservation: ReservationRecord) -> String? {
        let start = reservation.startLocation?.tripToolsNilIfEmpty
        let end = reservation.endLocation?.tripToolsNilIfEmpty
        switch (start, end) {
        case let (start?, end?):
            if start.caseInsensitiveCompare(end) == .orderedSame { return start }
            return "\(start) → \(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        case (nil, nil):
            return nil
        }
    }
}

// MARK: - Sections

private struct ReservationSection: Identifiable {
    let id: String
    let title: String
    var items: [ReservationRecord]
}

// MARK: - Add reservation

private struct AddReservationSheet: View {
    @ObservedObject var store: TripDetailStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wanderer.currency") private var preferredCurrency = "USD"

    @State private var type: ReservationType = .flight
    @State private var title = ""
    @State private var provider = ""
    @State private var confirmation = ""
    @State private var hasStart = true
    @State private var startAt = Date()
    @State private var hasEnd = false
    @State private var endAt = Date().addingTimeInterval(60 * 60 * 2)
    @State private var startLocation = ""
    @State private var endLocation = ""
    @State private var costText = ""
    @State private var currency = ""
    @State private var notes = ""

    @State private var isSaving = false

    private var canSave: Bool {
        !isSaving && !title.tripToolsTrimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TripToolFormCard {
                        Text("What are you booking?")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(ReservationType.allCases) { option in
                                TripToolChip(
                                    title: option.title,
                                    icon: option.icon,
                                    isSelected: type == option
                                ) {
                                    type = option
                                }
                            }
                        }
                    }

                    TripToolFormCard {
                        TripToolField(
                            label: "Title",
                            icon: "textformat",
                            placeholder: "Flight to Osaka",
                            text: $title
                        )
                        Divider().overlay(WandererTheme.line)
                        TripToolField(
                            label: "Provider",
                            icon: "building.2",
                            placeholder: "JAL, Airbnb, JR…",
                            text: $provider
                        )
                        Divider().overlay(WandererTheme.line)
                        TripToolField(
                            label: "Confirmation",
                            icon: "number",
                            placeholder: "ABC123",
                            text: $confirmation,
                            capitalization: .characters,
                            autocorrectionDisabled: true
                        )
                    }

                    TripToolFormCard {
                        Text("Schedule")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                        TripToolOptionalDate(title: "Start", isEnabled: $hasStart, date: $startAt)
                        Divider().overlay(WandererTheme.line)
                        TripToolOptionalDate(title: "End", isEnabled: $hasEnd, date: $endAt)
                    }

                    TripToolFormCard {
                        Text("Route")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                        TripToolField(
                            label: "From",
                            icon: "airplane.departure",
                            placeholder: "KIX",
                            text: $startLocation
                        )
                        Divider().overlay(WandererTheme.line)
                        TripToolField(
                            label: "To",
                            icon: "airplane.arrival",
                            placeholder: "Osaka",
                            text: $endLocation
                        )
                    }

                    TripToolFormCard {
                        HStack(alignment: .top, spacing: 14) {
                            TripToolField(
                                label: "Cost",
                                icon: "banknote",
                                placeholder: "0",
                                text: $costText,
                                keyboard: .decimalPad,
                                capitalization: .never
                            )
                            TripToolCurrencyField(currency: $currency)
                        }
                        Divider().overlay(WandererTheme.line)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)
                            TextField("Anything to remember", text: $notes, axis: .vertical)
                                .font(.ligga(.body, weight: .medium))
                                .foregroundStyle(WandererTheme.ink)
                                .lineLimit(2...4)
                        }
                    }

                    TripToolPrimaryButton(title: "Save booking", icon: "checkmark", isEnabled: canSave) {
                        save()
                    }
                    .accessibilityIdentifier("reservation-save")
                    .padding(.top, 4)

                    if title.tripToolsTrimmed.isEmpty {
                        Text("Add a title to save.")
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, TripToolsLayout.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("New booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WandererTheme.platinum, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if currency.isEmpty {
                    currency = preferredCurrency
                }
            }
        }
        .tint(WandererTheme.controlTint)
    }

    private func save() {
        let trimmedTitle = title.tripToolsTrimmed
        guard canSave, !trimmedTitle.isEmpty else { return }
        isSaving = true

        let resolvedCurrency = currency.tripToolsTrimmed.isEmpty
            ? preferredCurrency
            : currency.tripToolsTrimmed.uppercased()
        let resolvedProvider = provider.tripToolsNilIfEmpty
        let resolvedConfirmation = confirmation.tripToolsNilIfEmpty
        let resolvedStartLocation = startLocation.tripToolsNilIfEmpty
        let resolvedEndLocation = endLocation.tripToolsNilIfEmpty
        let resolvedNotes = notes.tripToolsNilIfEmpty
        let resolvedStart = hasStart ? startAt : nil
        let resolvedEnd = hasEnd ? endAt : nil
        let resolvedCost = parseCost(costText)

        Task {
            await store.addReservation(
                type: type,
                title: trimmedTitle,
                provider: resolvedProvider,
                confirmationCode: resolvedConfirmation,
                startAt: resolvedStart,
                endAt: resolvedEnd,
                startLocation: resolvedStartLocation,
                endLocation: resolvedEndLocation,
                cost: resolvedCost,
                currency: resolvedCurrency,
                notes: resolvedNotes
            )
            isSaving = false
            dismiss()
        }
    }

    private func parseCost(_ text: String) -> Double? {
        TripToolsParse.decimal(text)
    }
}
