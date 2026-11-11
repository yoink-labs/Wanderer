import Foundation
import SwiftUI

struct ChecklistView: View {
    /// The tick grows with the item text so it stays an obvious target.
    @ScaledMetric(relativeTo: .body) private var tickSize: CGFloat = 22
    @ObservedObject var store: TripDetailStore

    @State private var newItem = ""
    @State private var showDone = false
    @FocusState private var isAdding: Bool

    private static let suggestions = ["Passport", "Phone charger", "Travel adapter", "Medication", "Travel insurance"]

    private var pending: [ChecklistRecord] {
        store.checklist.filter { !$0.isChecked }
    }

    private var done: [ChecklistRecord] {
        store.checklist.filter(\.isChecked)
    }

    private var total: Int { store.checklist.count }
    private var checked: Int { done.count }
    private var progress: Double {
        total == 0 ? 0 : Double(checked) / Double(total)
    }
    private var canAdd: Bool { !newItem.tripToolsTrimmed.isEmpty }

    private var unusedSuggestions: [String] {
        let existing = Set(store.checklist.map { $0.title.lowercased() })
        return Self.suggestions.filter { !existing.contains($0.lowercased()) }
    }

    var body: some View {
        List {
            if total > 0 {
                progressCard
                    .tripToolListRow()
            }

            TripToolGroupLabel(title: "To pack", trailing: pending.isEmpty ? nil : "\(pending.count)")
                .tripToolListRow()

            ForEach(pending) { item in
                itemRow(item)
            }

            addRow
                .tripToolListRow()

            if total == 0 {
                suggestionsCard
                    .tripToolListRow()
            } else if pending.isEmpty {
                Label("Everything is packed", systemImage: "checkmark.seal")
                    .font(.ligga(.subheadline, weight: .medium))
                    .foregroundStyle(WandererTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .tripToolListRow()
            }

            if !done.isEmpty {
                doneHeader
                    .tripToolListRow()

                if showDone {
                    ForEach(done) { item in
                        itemRow(item)
                    }
                }
            }
        }
        .tripToolList()
        .animation(.easeOut(duration: 0.2), value: store.checklist)
        .animation(.easeOut(duration: 0.2), value: showDone)
    }

    // MARK: - Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(checked) of \(total) packed")
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WandererTheme.fillMuted)
                    Capsule()
                        .fill(WandererTheme.route)
                        .frame(width: progress > 0 ? max(8, proxy.size.width * CGFloat(progress)) : 0)
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.3), value: progress)
        }
        .padding(16)
        .liggaCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checklist progress")
        .accessibilityValue("\(checked) of \(total) packed")
    }

    // MARK: - Inline add

    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 24)
                .accessibilityHidden(true)

            TextField("Add an item", text: $newItem)
                .font(.ligga(.body))
                .foregroundStyle(WandererTheme.ink)
                .focused($isAdding)
                .submitLabel(.done)
                .onSubmit(addItem)
                .accessibilityLabel("New checklist item")
                .accessibilityIdentifier("checklist-new-item")

            if canAdd {
                Button("Add", action: addItem)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.onPrimary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(WandererTheme.primaryFill, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("checklist-add")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .liggaCard()
        .contentShape(Rectangle())
        .onTapGesture { isAdding = true }
    }

    private func addItem() {
        let trimmed = newItem.tripToolsTrimmed
        guard !trimmed.isEmpty else { return }
        newItem = ""
        // Keep the keyboard up so several items can be added in a row.
        isAdding = true
        Task { await store.addChecklistItem(title: trimmed) }
    }

    // MARK: - Empty state

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing on the list yet")
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
            Text("Type above, or start with a common one:")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)

            SuggestionFlow(spacing: 8) {
                ForEach(unusedSuggestions, id: \.self) { suggestion in
                    Button {
                        Task { await store.addChecklistItem(title: suggestion) }
                    } label: {
                        Label(suggestion, systemImage: "plus")
                            .font(.ligga(.footnote, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(WandererTheme.platinum, in: Capsule())
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(suggestion)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liggaCard()
    }

    // MARK: - Done group

    private var doneHeader: some View {
        Button {
            showDone.toggle()
        } label: {
            HStack {
                Text("Done")
                    .font(.ligga(.footnote, weight: .semibold))
                Text("\(done.count)")
                    .font(.ligga(.footnote))
                    .monospacedDigit()
                Spacer()
                Text(showDone ? "Hide" : "Show")
                    .font(.ligga(.footnote, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.ligga(.caption, weight: .semibold))
                    .rotationEffect(.degrees(showDone ? 0 : -90))
            }
            .foregroundStyle(WandererTheme.muted)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done items, \(done.count)")
        .accessibilityValue(showDone ? "Expanded" : "Collapsed")
        .accessibilityHint(showDone ? "Hides packed items" : "Shows packed items")
    }

    // MARK: - Rows

    private func itemRow(_ item: ChecklistRecord) -> some View {
        Button {
            Task { await store.toggleChecklist(item) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isChecked ? Color.clear : WandererTheme.dust, lineWidth: 2)
                    if item.isChecked {
                        Circle().fill(WandererTheme.route)
                        Image(systemName: "checkmark")
                            .font(.system(size: tickSize * 0.55, weight: .heavy))
                            .foregroundStyle(WandererTheme.onAccent)
                    }
                }
                .frame(width: tickSize, height: tickSize)
                .accessibilityHidden(true)

                Text(item.title)
                    .font(.ligga(.body))
                    .foregroundStyle(item.isChecked ? WandererTheme.muted : WandererTheme.ink)
                    .strikethrough(item.isChecked, color: WandererTheme.muted.opacity(0.7))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .liggaCard()
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.isChecked)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.isChecked ? "Packed" : "Not packed")
        .accessibilityAddTraits(item.isChecked ? [.isSelected] : [])
        .tripToolListRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await store.deleteChecklistItem(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(WandererTheme.coralDeep)
        }
        .contextMenu {
            Button {
                Task { await store.toggleChecklist(item) }
            } label: {
                Label(item.isChecked ? "Mark as not packed" : "Mark as packed",
                      systemImage: item.isChecked ? "circle" : "checkmark.circle")
            }
            Button(role: .destructive) {
                Task { await store.deleteChecklistItem(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Flow layout

/// Wraps suggestion chips onto as many lines as they need, so larger text
/// sizes never truncate them.
private struct SuggestionFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
