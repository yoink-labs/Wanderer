import Foundation
import SwiftUI
import UIKit

// MARK: - Tabs

enum TripToolTab: Hashable, CaseIterable {
    case reservations
    case expenses
    case checklist
    case share

    var title: String {
        switch self {
        case .reservations: return "Reservations"
        case .expenses: return "Expenses"
        case .checklist: return "Checklist"
        case .share: return "Share"
        }
    }

    var icon: String {
        switch self {
        case .reservations: return "ticket.fill"
        case .expenses: return "creditcard.fill"
        case .checklist: return "checkmark.circle.fill"
        case .share: return "person.2.fill"
        }
    }
}

// MARK: - Trip tools

/// Sheet that gathers the practical parts of a trip: bookings, spending,
/// the packing checklist and sharing.
struct TripToolsView: View {
    let trip: Trip
    @ObservedObject var store: TripDetailStore
    var initialTab: TripToolTab = .reservations

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: TripToolTab
    @State private var errorText: String?
    @State private var didRequestLoad = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showJournal = false

    init(trip: Trip, store: TripDetailStore, initialTab: TripToolTab = .reservations) {
        self.trip = trip
        self.store = store
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, TripToolsLayout.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                tabBar
                    .padding(.horizontal, TripToolsLayout.gutter)
                    .padding(.bottom, 8)

                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WandererTheme.platinum.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(WandererTheme.controlTint)
        .task {
            consumePendingError()
            guard !didRequestLoad else { return }
            didRequestLoad = true
            if store.reservations.isEmpty && store.expenses.isEmpty && store.checklist.isEmpty {
                await store.load()
            }
        }
        .onChange(of: store.errorMessage) { _, message in
            guard let message else { return }
            errorText = message
            store.errorMessage = nil
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showJournal) {
            TripJournalView(trip: trip, store: store)
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

    private var header: some View {
        HStack {
            Text("Trip tools")
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showJournal = true
            } label: {
                Image(systemName: "map")
                    .font(.ligga(.body, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trip journal")

            Button {
                exportPDF()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.ligga(.body, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export trip as PDF")
            .accessibilityIdentifier("trip-export-pdf")

            Button("Done") { dismiss() }
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip-tools-done")
        }
    }

    private func exportPDF() {
        guard let url = TripPDFExporter.writeTemporaryFile(
            trip: trip,
            days: store.days,
            places: store.places,
            reservations: store.reservations,
            expenses: store.expenses
        ) else {
            errorText = "Couldn't build the PDF. Try again."
            return
        }
        exportURL = url
        showShareSheet = true
        LiggaHaptics.success()
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(TripToolTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.ligga(.footnote, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selectedTab == tab ? WandererTheme.ink : WandererTheme.muted)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? WandererTheme.card : Color.clear)
                                .shadow(color: selectedTab == tab ? WandererTheme.shadow : .clear, radius: 3, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(WandererTheme.dust.opacity(0.45), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .reservations:
            ReservationsView(store: store)
        case .expenses:
            ExpensesView(store: store, tripID: trip.id)
        case .checklist:
            ChecklistView(store: store)
        case .share:
            ShareTripView(trip: trip, profiles: store.members)
        }
    }

    private func consumePendingError() {
        guard let message = store.errorMessage else { return }
        errorText = message
        store.errorMessage = nil
    }
}

// MARK: - Formatting helpers

enum TripToolsFormat {
    static func money(_ amount: Double, code: String) -> String {
        let resolvedCode = code.tripToolsTrimmed.isEmpty ? "USD" : code.tripToolsTrimmed.uppercased()
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = resolvedCode
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = abs(amount.rounded() - amount) < 0.005 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(resolvedCode) \(String(format: "%.2f", amount))"
    }

    static func date(fromISO value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

extension String {
    var tripToolsTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var tripToolsNilIfEmpty: String? {
        let trimmed = tripToolsTrimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Layout

enum TripToolsLayout {
    /// Horizontal page gutter shared by every trip tool screen.
    static let gutter: CGFloat = 16
    /// Height of the fade that sits above sticky bottom actions.
    static let fadeHeight: CGFloat = 24
}

// MARK: - Shared row chrome

extension View {
    /// Standard list-row chrome for the white cards used across trip tools.
    func tripToolListRow() -> some View {
        listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// Plain list styling shared by the trip tool lists: platinum canvas,
    /// 16pt gutters and no system section chrome.
    func tripToolList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(12)
            .contentMargins(.horizontal, TripToolsLayout.gutter, for: .scrollContent)
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .background(WandererTheme.platinum)
    }
}

/// Small uppercase group label rendered as a list row so it lines up with
/// the card edge instead of the system's inset section header.
struct TripToolGroupLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .monospacedDigit()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Sticky bottom action with a short platinum fade so content scrolling
/// underneath dissolves instead of being cut at a hard edge.
struct TripToolBottomBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [WandererTheme.platinum.opacity(0), WandererTheme.platinum],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: TripToolsLayout.fadeHeight)
            .allowsHitTesting(false)

            content
                .padding(.horizontal, TripToolsLayout.gutter)
                .padding(.bottom, 8)
                .background(WandererTheme.platinum)
        }
    }
}

/// Compact charcoal primary action used by trip tools.
struct TripToolPrimaryButton: View {
    let title: String
    var icon: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ligga(.subheadline, weight: .bold))
                }
                Text(title)
                    .font(.ligga(.headline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? WandererTheme.charcoal : WandererTheme.muted.opacity(0.35))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Secondary action: white surface, charcoal label, 44pt minimum height.
struct TripToolSecondaryButton: View {
    let title: String
    var icon: String?
    var fillsWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TripToolSecondaryLabel(title: title, icon: icon, fillsWidth: fillsWidth)
        }
        .buttonStyle(.plain)
    }
}

struct TripToolSecondaryLabel: View {
    let title: String
    var icon: String?
    var fillsWidth = true

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.ligga(.subheadline, weight: .semibold))
            }
            Text(title)
                .font(.ligga(.subheadline, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(WandererTheme.ink)
        .padding(.horizontal, 14)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
        .background(WandererTheme.platinum, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Empty state card with one clear next step.
struct TripToolEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var actionIcon: String = "plus"
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.ligga(.title2, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .frame(width: 56, height: 56)
                .background(WandererTheme.platinum, in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(title)
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                Text(message)
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                TripToolPrimaryButton(title: actionTitle, icon: actionIcon, action: action)
                    .frame(maxWidth: 260)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .liggaCard()
    }
}

// MARK: - Shared form pieces

struct TripToolFormCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liggaCard()
    }
}

struct TripToolField: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrectionDisabled = false

    var body: some View {
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
                TextField(placeholder, text: $text)
                    .font(.ligga(.body, weight: .medium))
                    .foregroundStyle(WandererTheme.ink)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(autocorrectionDisabled)
                    .accessibilityLabel(label)
            }
        }
        .frame(minHeight: 44)
    }
}

struct TripToolCurrencyField: View {
    @Binding var currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Currency")
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
            TextField("USD", text: $currency)
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(minWidth: 56, maxWidth: 72)
                .accessibilityLabel("Currency")
        }
    }
}

struct TripToolChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.ligga(.caption, weight: .semibold))
                Text(title)
                    .font(.ligga(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? .white : WandererTheme.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? WandererTheme.charcoal : WandererTheme.platinum)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Capsule filter chip used above lists.
struct TripToolFilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ligga(.caption, weight: .semibold))
                }
                Text(title)
                    .font(.ligga(.footnote, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(isSelected ? .white : WandererTheme.ink)
            .background(isSelected ? WandererTheme.charcoal : WandererTheme.card, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : WandererTheme.line, lineWidth: 1))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct TripToolOptionalDate: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isEnabled) {
                Text(title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
            }
            .tint(WandererTheme.controlTint)

            if isEnabled {
                DatePicker(title, selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(WandererTheme.controlTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Parsing

enum TripToolsParse {
    /// Lenient decimal parsing for money and split inputs: accepts comma
    /// decimals and strips common currency symbols, spaces and percent signs.
    static func decimal(_ text: String) -> Double? {
        var cleaned = text.tripToolsTrimmed
        for symbol in ["$", "€", "£", "¥", "%", " "] {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}
