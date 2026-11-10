import Foundation
import SwiftUI

struct ExpensesView: View {
    @ObservedObject var store: TripDetailStore
    @AppStorage("wanderer.currency") private var tripCurrency = "USD"
    /// Optional per-trip budget, stored on device and keyed by trip id.
    /// Zero means no budget has been set.
    @AppStorage private var budget: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showAdd = false
    @State private var showBudget = false
    @State private var settlePrefill: SettlePrefill?
    @State private var convertedTotal: Double?

    init(store: TripDetailStore, tripID: UUID) {
        self.store = store
        _budget = AppStorage(wrappedValue: 0, "wanderer.budget.\(tripID.uuidString)")
    }

    var body: some View {
        List {
            totalCard
                .tripToolListRow()

            if store.members.count > 1 {
                balancesCard
                    .tripToolListRow()
            }

            if store.expenses.isEmpty {
                TripToolEmptyState(
                    icon: "creditcard",
                    title: "No expenses yet",
                    message: "Log the first meal, stay or ride. Totals, the budget and who owes whom fill in from there.",
                    actionTitle: "Add expense"
                ) {
                    showAdd = true
                }
                .tripToolListRow()
                .accessibilityIdentifier("expenses-empty-add")
            } else {
                breakdownCard
                    .tripToolListRow()

                TripToolGroupLabel(title: "Expenses", trailing: "\(store.expenses.count)")
                    .tripToolListRow()

                ForEach(store.expenses) { expense in
                    row(for: expense)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await store.deleteExpense(expense) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(WandererTheme.coralDeep)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await store.deleteExpense(expense) }
                            } label: {
                                Label("Delete expense", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .tripToolList()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.expenses.isEmpty {
                TripToolBottomBar {
                    TripToolPrimaryButton(title: "Add expense", icon: "plus") {
                        showAdd = true
                    }
                    .accessibilityIdentifier("expenses-add")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseSheet(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $settlePrefill) { prefill in
            SettleUpSheet(store: store, prefill: prefill)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBudget) {
            BudgetSheet(budget: $budget, currency: currencyCode, spent: spent)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task(id: conversionKey) {
            await convertTotal()
        }
    }

    // MARK: - Derived data

    private var currencyCode: String {
        tripCurrency.tripToolsTrimmed.isEmpty ? "USD" : tripCurrency.tripToolsTrimmed.uppercased()
    }

    /// Spend in the trip currency: the converted total when foreign
    /// expenses could be converted, otherwise the logged sum.
    private var spent: Double {
        convertedTotal ?? store.totalExpenses
    }

    private var hasMixedCurrencies: Bool {
        Set(store.expenses.map { currencyCode(for: $0).uppercased() }).count > 1
    }

    private var slices: [CategorySlice] {
        store.expensesByCategory.map { CategorySlice(category: $0.0, amount: $0.1) }
    }

    private var suggestions: [SuggestedPayment] {
        SettleSuggestions.payments(from: store.memberBalances)
    }

    private var conversionKey: String {
        let items = store.expenses.map { "\($0.id.uuidString)-\($0.currency)" }.joined(separator: ",")
        return "\(tripCurrency)|\(items)"
    }

    private func fraction(for slice: CategorySlice) -> Double {
        guard store.totalExpenses > 0 else { return 0 }
        return slice.amount / store.totalExpenses
    }

    private func tint(for category: ExpenseCategory) -> Color {
        switch category {
        case .food: return WandererTheme.salmon
        case .lodging: return WandererTheme.desert
        case .transport: return WandererTheme.charcoal
        case .activities: return WandererTheme.peach
        case .shopping: return WandererTheme.dust
        case .other: return WandererTheme.muted
        }
    }

    private func dateLabel(for expense: ExpenseRecord) -> String {
        if let date = TripToolsFormat.parseDay(expense.spentAt) {
            return TripToolsFormat.shortDate(date)
        }
        return expense.spentAt
    }

    private func currencyCode(for expense: ExpenseRecord) -> String {
        expense.currency.tripToolsTrimmed.isEmpty ? currencyCode : expense.currency
    }

    private func name(_ id: UUID?) -> String {
        guard let id else { return "Someone" }
        if id == store.currentUserId { return "You" }
        return store.members.first(where: { $0.userId == id })?.displayName ?? "Trip member"
    }

    private func money(_ value: Double) -> String {
        TripToolsFormat.money(value, code: currencyCode)
    }

    private static func percentLabel(_ fraction: Double) -> String {
        let value = fraction * 100
        if value > 0, value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    // MARK: - Total card

    private var totalCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return VStack(alignment: .leading, spacing: 14) {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total spent")
                        .font(.ligga(.footnote, weight: .semibold))
                        .foregroundStyle(WandererTheme.muted)
                    Text(money(spent))
                        .font(.ligga(.title, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(totalCaption)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }

                if store.members.count > 1 {
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        Text("Per person")
                            .font(.ligga(.footnote, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                        Text(money(spent / Double(store.members.count)))
                            .font(.ligga(.title3, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WandererTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            budgetSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liggaCard()
    }

    private var totalCaption: String {
        let count = "\(store.expenses.count) \(store.expenses.count == 1 ? "expense" : "expenses")"
        if convertedTotal != nil {
            return "\(count) · converted to \(currencyCode)"
        }
        if hasMixedCurrencies {
            return "\(count) · mixed currencies, not converted"
        }
        return "\(count) · \(currencyCode)"
    }

    @ViewBuilder
    private var budgetSection: some View {
        if budget > 0 {
            let used = spent / budget
            let isOver = spent > budget + 0.005

            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(WandererTheme.line)

                HStack(alignment: .firstTextBaseline) {
                    Text(isOver
                         ? "\(money(spent - budget)) over budget"
                         : "\(money(budget - spent)) left")
                        .font(.ligga(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOver ? WandererTheme.coralDeep : WandererTheme.ink)

                    Spacer(minLength: 8)

                    Button("Edit") { showBudget = true }
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit budget")
                }

                BudgetBar(fraction: used, isOver: isOver)
                    .accessibilityHidden(true)

                Text("\(Self.percentLabel(used)) of \(money(budget)) budget")
                    .font(.ligga(.caption))
                    .monospacedDigit()
                    .foregroundStyle(WandererTheme.muted)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isOver
                                ? "Budget \(money(budget)), \(money(spent - budget)) over"
                                : "Budget \(money(budget)), \(money(budget - spent)) left")
        } else {
            Button {
                showBudget = true
            } label: {
                TripToolSecondaryLabel(title: "Set a budget", icon: "target", fillsWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("expenses-set-budget")
        }
    }

    // MARK: - Balances

    private var balancesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Balances")
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Button {
                    let first = suggestions.first
                    settlePrefill = SettlePrefill(
                        from: first?.from.userId,
                        to: first?.to.userId,
                        amount: first?.amount
                    )
                } label: {
                    Text("Settle up")
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(WandererTheme.charcoal, in: Capsule())
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("expenses-settle-up")
            }

            VStack(spacing: 0) {
                ForEach(Array(store.memberBalances.enumerated()), id: \.element.id) { index, balance in
                    if index > 0 {
                        Divider().overlay(WandererTheme.line)
                    }
                    balanceRow(balance)
                }
            }

            if !store.expenses.isEmpty {
                Divider().overlay(WandererTheme.line)

                if suggestions.isEmpty {
                    Label("Everyone is settled up", systemImage: "checkmark.circle")
                        .font(.ligga(.subheadline, weight: .medium))
                        .foregroundStyle(WandererTheme.muted)
                        .frame(minHeight: 32)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(suggestions.count == 1 ? "Suggested payment" : "Fewest payments to settle")
                            .font(.ligga(.footnote, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                            .padding(.bottom, 2)

                        ForEach(suggestions) { suggestion in
                            suggestionRow(suggestion)
                        }
                    }
                }
            }
        }
        .padding(16)
        .liggaCard()
    }

    private func balanceRow(_ balance: MemberBalance) -> some View {
        let isYou = balance.member.userId == store.currentUserId
        let status: String = balance.isOwed
            ? (isYou ? "get back" : "gets back")
            : (balance.owes ? (isYou ? "owe" : "owes") : "settled up")

        return HStack(spacing: 10) {
            Text(balance.member.initials)
                .font(.ligga(.caption, weight: .bold))
                .foregroundStyle(WandererTheme.ink)
                .frame(width: 34, height: 34)
                .background(WandererTheme.platinum, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(isYou ? "You" : balance.member.displayName)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                Label(status, systemImage: balance.isOwed ? "arrow.down.left" : (balance.owes ? "arrow.up.right" : "checkmark"))
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
            }

            Spacer(minLength: 6)

            Text(money(abs(balance.net)))
                .font(.ligga(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(balanceColor(balance))
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(balance.isOwed || balance.owes
                            ? "\(isYou ? "You" : balance.member.displayName) \(status) \(money(abs(balance.net)))"
                            : "\(isYou ? "You" : balance.member.displayName), settled up")
    }

    private func suggestionRow(_ suggestion: SuggestedPayment) -> some View {
        let fromName = name(suggestion.from.userId)
        let toName = name(suggestion.to.userId)
        let verb = fromName == "You" ? "pay" : "pays"

        return Button {
            settlePrefill = SettlePrefill(
                from: suggestion.from.userId,
                to: suggestion.to.userId,
                amount: suggestion.amount
            )
        } label: {
            HStack(spacing: 8) {
                Text("\(fromName) \(verb) \(toName)")
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Text(money(suggestion.amount))
                    .font(.ligga(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WandererTheme.ink)
                Image(systemName: "chevron.right")
                    .font(.ligga(.caption, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fromName) \(verb) \(toName) \(money(suggestion.amount))")
        .accessibilityHint("Opens settle up with this payment filled in")
    }

    private func balanceColor(_ balance: MemberBalance) -> Color {
        if balance.owes { return WandererTheme.coralDeep }
        if balance.isOwed { return WandererTheme.charcoal }
        return WandererTheme.muted
    }

    // MARK: - Category breakdown

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By category")
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .accessibilityAddTraits(.isHeader)

            GeometryReader { proxy in
                let gaps = CGFloat(max(0, slices.count - 1)) * 2
                let usable = max(0, proxy.size.width - gaps)
                HStack(spacing: 2) {
                    ForEach(slices) { slice in
                        Rectangle()
                            .fill(tint(for: slice.category))
                            .frame(width: max(4, usable * CGFloat(fraction(for: slice))))
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                ForEach(slices) { slice in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(tint(for: slice.category))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(slice.category.title)
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.ink)
                        Spacer(minLength: 6)
                        Text(Self.percentLabel(fraction(for: slice)))
                            .font(.ligga(.footnote))
                            .monospacedDigit()
                            .foregroundStyle(WandererTheme.muted)
                        Text(TripToolsFormat.money(slice.amount, code: currencyCode))
                            .font(.ligga(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WandererTheme.ink)
                    }
                    .frame(minHeight: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(slice.category.title), \(TripToolsFormat.money(slice.amount, code: currencyCode)), \(Self.percentLabel(fraction(for: slice))) of spending")
                }
            }
        }
        .padding(16)
        .liggaCard()
    }

    // MARK: - Rows

    private func row(for expense: ExpenseRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .frame(width: 38, height: 38)
                .background(tint(for: expense.category).opacity(0.28), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)

                Text(rowSubtitle(for: expense))
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Text(TripToolsFormat.money(expense.amount, code: currencyCode(for: expense)))
                .font(.ligga(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WandererTheme.ink)
        }
        .padding(14)
        .liggaCard()
        .accessibilityElement(children: .combine)
        .tripToolListRow()
    }

    private func rowSubtitle(for expense: ExpenseRecord) -> String {
        var parts = [expense.category.title, dateLabel(for: expense)]
        if expense.paidBy != nil {
            parts.append("paid by \(name(expense.paidBy))")
        }
        switch expense.splitMode {
        case .equal: break
        case .exact: parts.append("exact split")
        case .percent: parts.append("% split")
        case .shares: parts.append("split by shares")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Currency conversion

    /// Best-effort conversion of foreign-currency expenses into the trip
    /// currency. Failures are silent so the screen never blocks on rates.
    private func convertTotal() async {
        let target = tripCurrency.tripToolsTrimmed.uppercased()
        guard !store.expenses.isEmpty else {
            convertedTotal = nil
            return
        }

        let groups = Dictionary(grouping: store.expenses) { expense -> String in
            let code = expense.currency.tripToolsTrimmed.uppercased()
            return code.isEmpty ? target : code
        }

        var converted = 0.0
        var convertedAny = false
        var failed = false

        for (code, items) in groups {
            let sum = items.reduce(0) { $0 + $1.amount }
            if code == target {
                converted += sum
                continue
            }
            do {
                if let rate = try await CurrencyService.rate(from: code, to: target) {
                    converted += sum * rate
                    convertedAny = true
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }

        if failed || !convertedAny {
            convertedTotal = nil
        } else {
            convertedTotal = converted
        }
    }
}


// MARK: - Category slices

private struct CategorySlice: Identifiable {
    let category: ExpenseCategory
    let amount: Double

    var id: String { category.rawValue }
}

// MARK: - Budget

private struct BudgetBar: View {
    let fraction: Double
    let isOver: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WandererTheme.platinum)
                Capsule()
                    .fill(isOver ? WandererTheme.peach : WandererTheme.charcoal)
                    .frame(width: max(fraction > 0 ? 6 : 0, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 6)
    }
}

private struct BudgetSheet: View {
    @Binding var budget: Double
    let currency: String
    let spent: Double

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var parsed: Double? {
        TripToolsParse.decimal(text)
    }

    private var canSave: Bool {
        (parsed ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TripToolFormCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trip budget (\(currency))")
                            .font(.ligga(.caption))
                            .foregroundStyle(WandererTheme.muted)
                        TextField("2000", text: $text)
                            .font(.ligga(.title2, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WandererTheme.ink)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Trip budget in \(currency)")
                    }
                }

                Text(helperText)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if budget > 0 {
                    Button(role: .destructive) {
                        budget = 0
                        dismiss()
                    } label: {
                        Text("Remove budget")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.coralDeep)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, TripToolsLayout.gutter)
            .padding(.top, 8)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle(budget > 0 ? "Edit budget" : "Set a budget")
            .navigationBarTitleDisplayMode(.inline)
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
                if budget > 0 {
                    text = budget.rounded() == budget
                        ? String(format: "%.0f", budget)
                        : String(format: "%.2f", budget)
                }
                isFocused = true
            }
        }
        .tint(WandererTheme.controlTint)
    }

    private var helperText: String {
        let base = "Saved on this device for this trip."
        guard let parsed, parsed > 0 else { return base }
        let remaining = parsed - spent
        if remaining >= 0 {
            return "\(TripToolsFormat.money(remaining, code: currency)) left after \(TripToolsFormat.money(spent, code: currency)) spent. \(base)"
        }
        return "Already \(TripToolsFormat.money(-remaining, code: currency)) over with \(TripToolsFormat.money(spent, code: currency)) spent. \(base)"
    }

    private func save() {
        guard let parsed, parsed > 0 else { return }
        budget = (parsed * 100).rounded() / 100
        dismiss()
    }
}

// MARK: - Settle suggestions

/// Prefill for the settle-up sheet. `nil` fields fall back to the sheet's
/// own defaults.
struct SettlePrefill: Identifiable {
    let id = UUID()
    var from: UUID?
    var to: UUID?
    var amount: Double?
}

struct SuggestedPayment: Identifiable, Hashable {
    let from: TripMemberProfile
    let to: TripMemberProfile
    let amount: Double

    var id: String { "\(from.userId.uuidString)->\(to.userId.uuidString)" }
}

enum SettleSuggestions {
    /// Greedy debt simplification: repeatedly match the largest debtor with
    /// the largest creditor and pay the smaller of the two amounts. Works in
    /// whole cents so rounding residue never produces a $0.00 payment.
    static func payments(from balances: [MemberBalance]) -> [SuggestedPayment] {
        var debtors: [(member: TripMemberProfile, cents: Int)] = balances.compactMap { balance in
            let cents = Int((-balance.net * 100).rounded())
            return cents > 0 ? (balance.member, cents) : nil
        }
        var creditors: [(member: TripMemberProfile, cents: Int)] = balances.compactMap { balance in
            let cents = Int((balance.net * 100).rounded())
            return cents > 0 ? (balance.member, cents) : nil
        }

        var result: [SuggestedPayment] = []
        var iterations = 0
        let limit = (debtors.count + creditors.count) * 2

        while !debtors.isEmpty, !creditors.isEmpty, iterations <= limit {
            iterations += 1
            debtors.sort { $0.cents > $1.cents }
            creditors.sort { $0.cents > $1.cents }

            let pay = min(debtors[0].cents, creditors[0].cents)
            if pay > 0, debtors[0].member.userId != creditors[0].member.userId {
                result.append(SuggestedPayment(
                    from: debtors[0].member,
                    to: creditors[0].member,
                    amount: Double(pay) / 100
                ))
            }
            debtors[0].cents -= pay
            creditors[0].cents -= pay
            debtors.removeAll { $0.cents <= 0 }
            creditors.removeAll { $0.cents <= 0 }
        }
        return result
    }
}

// MARK: - Add expense

private struct AddExpenseSheet: View {
    @ObservedObject var store: TripDetailStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wanderer.currency") private var preferredCurrency = "USD"

    @State private var title = ""
    @State private var amountText = ""
    @State private var currency = ""
    @State private var category: ExpenseCategory = .food
    @State private var spentAt = Date()
    @State private var notes = ""

    @State private var paidBy: UUID?
    @State private var splitMode: ExpenseSplitMode = .equal
    @State private var selectedMembers: Set<UUID> = []
    @State private var splitInputs: [UUID: String] = [:]
    /// True while split inputs still hold the values we generated, so they
    /// can follow amount and participant changes without losing user edits.
    @State private var inputsAutoFilled = true
    @State private var isSaving = false

    // MARK: Derived values

    private var amount: Double {
        max(0, TripToolsParse.decimal(amountText) ?? 0)
    }

    private var orderedParticipants: [UUID] {
        store.members.map(\.userId).filter { selectedMembers.contains($0) }
    }

    private func inputValue(_ id: UUID) -> Double? {
        let raw = splitInputs[id]?.tripToolsTrimmed ?? ""
        if raw.isEmpty { return 0 }
        return TripToolsParse.decimal(raw)
    }

    private var hasInvalidInput: Bool {
        orderedParticipants.contains { id in
            guard let value = inputValue(id) else { return true }
            return value < 0
        }
    }

    private var splitTotal: Double {
        orderedParticipants.reduce(0) { $0 + max(0, inputValue($1) ?? 0) }
    }

    private var previewAmounts: [UUID: Double] {
        SplitMath.amounts(
            total: amount,
            mode: splitMode,
            participants: orderedParticipants,
            inputs: orderedParticipants.reduce(into: [UUID: Double]()) { $0[$1] = max(0, inputValue($1) ?? 0) }
        )
    }

    private var equalShare: Double {
        amount / Double(max(1, selectedMembers.count))
    }

    private var resolvedCurrency: String {
        currency.tripToolsTrimmed.isEmpty
            ? (preferredCurrency.tripToolsTrimmed.isEmpty ? "USD" : preferredCurrency)
            : currency.tripToolsTrimmed.uppercased()
    }

    private func money(_ value: Double) -> String {
        TripToolsFormat.money(value, code: resolvedCurrency)
    }

    private static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Validation copy for the current split plus whether it allows saving.
    private var splitStatus: (text: String, isValid: Bool) {
        let count = selectedMembers.count
        guard count > 0 else {
            return ("Choose at least one person to split with.", false)
        }
        if splitMode != .equal, hasInvalidInput {
            return ("Use numbers only, like 12.50.", false)
        }

        switch splitMode {
        case .equal:
            let people = count == 1 ? "1 person" : "\(count) people"
            return amount > 0
                ? ("\(money(equalShare)) each · \(people)", true)
                : ("Split equally between \(people).", true)

        case .exact:
            guard amount > 0 else {
                return ("Enter the total first, then each person's part.", false)
            }
            let difference = amount - splitTotal
            if abs(difference) < 0.01 {
                return ("Adds up to \(money(amount)).", true)
            }
            return difference > 0
                ? ("\(money(difference)) left to assign of \(money(amount)).", false)
                : ("\(money(-difference)) more than the \(money(amount)) total.", false)

        case .percent:
            let difference = 100 - splitTotal
            if abs(difference) < 0.01 {
                return ("Adds up to 100%.", true)
            }
            return difference > 0
                ? ("\(Self.number(difference))% left to assign (\(Self.number(splitTotal))% of 100%).", false)
                : ("\(Self.number(-difference))% over 100% (\(Self.number(splitTotal))%).", false)

        case .shares:
            guard splitTotal > 0 else {
                return ("Give at least one person a share.", false)
            }
            let shares = "\(Self.number(splitTotal)) \(splitTotal == 1 ? "share" : "shares")"
            return amount > 0
                ? ("\(shares) · \(money(amount / splitTotal)) per share", true)
                : ("\(shares) in total.", true)
        }
    }

    private var canSave: Bool {
        !isSaving
            && !title.tripToolsTrimmed.isEmpty
            && amount > 0
            && splitStatus.isValid
    }

    private var saveHint: String? {
        if title.tripToolsTrimmed.isEmpty && amount <= 0 { return "Add a title and amount to save." }
        if title.tripToolsTrimmed.isEmpty { return "Add a title to save." }
        if amount <= 0 { return "Add an amount to save." }
        if !splitStatus.isValid { return "Fix the split to save." }
        return nil
    }

    private func memberName(_ id: UUID) -> String {
        if id == store.currentUserId { return "You" }
        return store.members.first(where: { $0.userId == id })?.displayName ?? "Member"
    }

    private var splitPlaceholder: String {
        switch splitMode {
        case .exact: return "0.00"
        case .percent: return "0"
        case .shares: return "1"
        case .equal: return ""
        }
    }

    private var splitSuffix: String {
        switch splitMode {
        case .exact: return resolvedCurrency
        case .percent: return "%"
        case .shares: return "×"
        case .equal: return ""
        }
    }

    private var splitInputLabel: String {
        switch splitMode {
        case .exact: return "amount"
        case .percent: return "percent"
        case .shares: return "shares"
        case .equal: return ""
        }
    }

    private func inputBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { splitInputs[id] ?? "" },
            set: {
                splitInputs[id] = $0
                inputsAutoFilled = false
            }
        )
    }

    // MARK: Split input management

    private func toggleMember(_ id: UUID) {
        let isAdding = !selectedMembers.contains(id)
        if isAdding {
            selectedMembers.insert(id)
        } else {
            selectedMembers.remove(id)
        }

        guard splitMode != .equal else { return }
        if inputsAutoFilled {
            prepareSplitInputs(for: splitMode)
        } else {
            splitInputs[id] = isAdding && splitMode == .shares ? "1" : ""
        }
    }

    /// Seeds inputs so the split is valid immediately. Exact amounts and
    /// percentages are spread in hundredths with the remainder on the first
    /// people, so they always add up to the total (100 / 3 → 33.34, 33.33, 33.33).
    private func prepareSplitInputs(for mode: ExpenseSplitMode) {
        let participants = orderedParticipants
        for id in store.members.map(\.userId) where !selectedMembers.contains(id) {
            splitInputs[id] = ""
        }

        switch mode {
        case .equal:
            for id in participants { splitInputs[id] = "" }
        case .exact:
            for (id, part) in zip(participants, Self.evenParts(of: amount, count: participants.count)) {
                splitInputs[id] = String(format: "%.2f", part)
            }
        case .percent:
            for (id, part) in zip(participants, Self.evenParts(of: 100, count: participants.count)) {
                splitInputs[id] = Self.number(part)
            }
        case .shares:
            for id in participants { splitInputs[id] = "1" }
        }
        inputsAutoFilled = true
    }

    private static func evenParts(of total: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let units = Int((total * 100).rounded())
        let base = units / count
        let remainder = units - base * count
        return (0..<count).map { Double(base + ($0 < remainder ? 1 : 0)) / 100 }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TripToolFormCard {
                        TripToolField(
                            label: "Title",
                            icon: "textformat",
                            placeholder: "Dinner in Gion",
                            text: $title
                        )
                        Divider().overlay(WandererTheme.line)
                        HStack(alignment: .top, spacing: 14) {
                            TripToolField(
                                label: "Amount",
                                icon: "banknote",
                                placeholder: "0",
                                text: $amountText,
                                keyboard: .decimalPad,
                                capitalization: .never
                            )
                            TripToolCurrencyField(currency: $currency)
                        }
                    }

                    TripToolFormCard {
                        Text("Category")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(ExpenseCategory.allCases) { option in
                                TripToolChip(
                                    title: option.title,
                                    icon: option.icon,
                                    isSelected: category == option
                                ) {
                                    category = option
                                }
                            }
                        }
                    }

                    splitCard

                    TripToolFormCard {
                        DatePicker(selection: $spentAt, displayedComponents: .date) {
                            Text("Date")
                                .font(.ligga(.subheadline, weight: .semibold))
                                .foregroundStyle(WandererTheme.muted)
                        }
                        .datePickerStyle(.compact)
                        .tint(WandererTheme.controlTint)
                        .frame(minHeight: 44)

                        Divider().overlay(WandererTheme.line)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)
                            TextField("What was it for?", text: $notes, axis: .vertical)
                                .font(.ligga(.body, weight: .medium))
                                .foregroundStyle(WandererTheme.ink)
                                .lineLimit(2...4)
                                .accessibilityLabel("Notes")
                        }
                    }

                    VStack(spacing: 8) {
                        TripToolPrimaryButton(title: "Save expense", icon: "checkmark", isEnabled: canSave) {
                            save()
                        }
                        .accessibilityIdentifier("expense-save")

                        if let saveHint {
                            Text(saveHint)
                                .font(.ligga(.footnote))
                                .foregroundStyle(WandererTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, TripToolsLayout.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("New expense")
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
                        .accessibilityIdentifier("expense-save-toolbar")
                }
            }
            .onAppear {
                if currency.isEmpty {
                    currency = preferredCurrency
                }
                if selectedMembers.isEmpty {
                    selectedMembers = Set(store.members.map(\.userId))
                }
                if paidBy == nil {
                    paidBy = store.currentUserId ?? store.members.first?.userId
                }
                prepareSplitInputs(for: splitMode)
            }
            .onChange(of: amountText) { _, _ in
                if splitMode == .exact, inputsAutoFilled {
                    prepareSplitInputs(for: .exact)
                }
            }
        }
        .tint(WandererTheme.controlTint)
    }

    private var splitCard: some View {
        TripToolFormCard {
            HStack {
                Text("Paid by")
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
                Spacer()
                Menu {
                    ForEach(store.members) { member in
                        Button(memberName(member.userId)) {
                            paidBy = member.userId
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(paidBy.map(memberName) ?? "Choose")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.ligga(.caption2, weight: .bold))
                            .foregroundStyle(WandererTheme.muted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Paid by \(paidBy.map(memberName) ?? "nobody yet")")
            }

            Divider().overlay(WandererTheme.line)

            Text("Split")
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 8)], spacing: 8) {
                ForEach(ExpenseSplitMode.allCases) { mode in
                    TripToolChip(
                        title: mode.title,
                        icon: mode.icon,
                        isSelected: splitMode == mode
                    ) {
                        guard splitMode != mode else { return }
                        splitMode = mode
                        prepareSplitInputs(for: mode)
                    }
                }
            }

            VStack(spacing: 2) {
                ForEach(store.members) { member in
                    memberSplitRow(member.userId)
                }
            }

            Label(splitStatus.text, systemImage: splitStatus.isValid ? "checkmark.circle" : "exclamationmark.circle")
                .font(.ligga(.footnote, weight: .medium))
                .foregroundStyle(splitStatus.isValid ? WandererTheme.muted : WandererTheme.coralDeep)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("expense-split-status")
        }
    }

    private func memberSplitRow(_ id: UUID) -> some View {
        let isSelected = selectedMembers.contains(id)
        let name = memberName(id)

        return HStack(spacing: 10) {
            Button {
                toggleMember(id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.ligga(.title3, weight: .semibold))
                        .foregroundStyle(isSelected ? WandererTheme.charcoal : WandererTheme.muted.opacity(0.5))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.ligga(.body))
                            .foregroundStyle(WandererTheme.ink)
                            .lineLimit(1)
                        if isSelected, splitMode == .percent || splitMode == .shares,
                           let share = previewAmounts[id], amount > 0 {
                            Text(money(share))
                                .font(.ligga(.caption))
                                .monospacedDigit()
                                .foregroundStyle(WandererTheme.muted)
                        }
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(isSelected ? "Included in split" : "Not included")
            .accessibilityHint("Double tap to \(isSelected ? "remove from" : "add to") the split")

            Spacer(minLength: 6)

            if splitMode == .equal {
                Text(isSelected && amount > 0 ? money(equalShare) : "—")
                    .font(.ligga(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? WandererTheme.ink : WandererTheme.muted)
            } else {
                HStack(spacing: 4) {
                    TextField(splitPlaceholder, text: inputBinding(for: id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.ligga(.body, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.ink)
                        .frame(minWidth: 56, maxWidth: 104)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("\(name) \(splitInputLabel)")
                    Text(splitSuffix)
                        .font(.ligga(.footnote, weight: .medium))
                        .foregroundStyle(WandererTheme.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(WandererTheme.platinum, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isSelected ? 1 : 0.4)
                .disabled(!isSelected)
            }
        }
    }

    private func save() {
        let trimmedTitle = title.tripToolsTrimmed
        guard canSave, !trimmedTitle.isEmpty, amount > 0 else { return }

        let resolvedNotes = notes.tripToolsNilIfEmpty
        let splitAmounts = previewAmounts
        guard !splitAmounts.isEmpty else { return }
        isSaving = true

        Task {
            await store.addExpense(
                title: trimmedTitle,
                amount: amount,
                currency: resolvedCurrency,
                category: category,
                paidBy: paidBy,
                splitMode: splitMode,
                splitAmounts: splitAmounts,
                spentAt: spentAt,
                notes: resolvedNotes
            )
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Settle up

private struct SettleUpSheet: View {
    @ObservedObject var store: TripDetailStore
    var prefill: SettlePrefill?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("wanderer.currency") private var preferredCurrency = "USD"

    @State private var fromUser: UUID?
    @State private var toUser: UUID?
    @State private var amountText = ""
    @State private var note = ""
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var didSeed = false

    private var amount: Double {
        TripToolsParse.decimal(amountText) ?? 0
    }

    private var canSave: Bool {
        guard !isSaving, let fromUser, let toUser, fromUser != toUser else { return false }
        return amount > 0
    }

    private var currency: String {
        preferredCurrency.tripToolsTrimmed.isEmpty ? "USD" : preferredCurrency.tripToolsTrimmed.uppercased()
    }

    private var summary: (text: String, isValid: Bool)? {
        guard let fromUser, let toUser else { return ("Choose who paid and who received it.", false) }
        if fromUser == toUser { return ("Choose two different people.", false) }
        guard amount > 0 else { return ("Enter the amount paid.", false) }
        let verb = name(fromUser) == "You" ? "pay" : "pays"
        return ("\(name(fromUser)) \(verb) \(name(toUser)) \(TripToolsFormat.money(amount, code: currency))", true)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TripToolFormCard {
                        memberPicker(title: "From", selection: $fromUser)
                        Divider().overlay(WandererTheme.line)
                        memberPicker(title: "To", selection: $toUser)
                    }

                    TripToolFormCard {
                        TripToolField(
                            label: "Amount (\(currency))",
                            icon: "banknote",
                            placeholder: "0",
                            text: $amountText,
                            keyboard: .decimalPad,
                            capitalization: .never
                        )
                        Divider().overlay(WandererTheme.line)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note")
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)
                            TextField("Optional", text: $note, axis: .vertical)
                                .font(.ligga(.body, weight: .medium))
                                .lineLimit(2...3)
                                .accessibilityLabel("Note")
                        }
                    }

                    if let summary {
                        Label(summary.text, systemImage: summary.isValid ? "arrow.right.circle" : "exclamationmark.circle")
                            .font(.ligga(.footnote, weight: .medium))
                            .foregroundStyle(summary.isValid ? WandererTheme.ink : WandererTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TripToolPrimaryButton(title: "Record payment", icon: "checkmark", isEnabled: canSave) {
                        save()
                    }
                    .padding(.top, 4)

                    Text("Records a payment made outside the app. Balances update right away.")
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, TripToolsLayout.gutter)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WandererTheme.platinum.ignoresSafeArea())
            .navigationTitle("Settle up")
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear(perform: seed)
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

    private func memberPicker(title: String, selection: Binding<UUID?>) -> some View {
        HStack {
            Text(title)
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
            Spacer()
            Menu {
                ForEach(store.members) { member in
                    Button(name(member.userId)) {
                        selection.wrappedValue = member.userId
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue.map(name) ?? "Choose")
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.ligga(.caption2, weight: .bold))
                        .foregroundStyle(WandererTheme.muted)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(title): \(selection.wrappedValue.map(name) ?? "not chosen")")
        }
    }

    private func name(_ id: UUID) -> String {
        if id == store.currentUserId { return "You" }
        return store.members.first(where: { $0.userId == id })?.displayName ?? "Member"
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true

        if let prefill, prefill.from != nil || prefill.to != nil {
            fromUser = prefill.from
            toUser = prefill.to
            if let value = prefill.amount, value > 0 {
                amountText = String(format: "%.2f", value)
            }
            return
        }

        if let first = SettleSuggestions.payments(from: store.memberBalances).first {
            fromUser = first.from.userId
            toUser = first.to.userId
            amountText = String(format: "%.2f", first.amount)
        } else {
            fromUser = store.currentUserId
        }
    }

    private func save() {
        guard canSave, let fromUser, let toUser else { return }
        isSaving = true
        Task {
            await store.settleUp(
                from: fromUser,
                to: toUser,
                amount: amount,
                currency: currency,
                note: note.tripToolsNilIfEmpty
            )
            isSaving = false
            if store.errorMessage == nil {
                dismiss()
            } else {
                errorText = store.errorMessage
            }
        }
    }
}
