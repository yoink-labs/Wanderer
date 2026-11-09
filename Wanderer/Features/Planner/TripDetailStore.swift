import Foundation
import Supabase

@MainActor
final class TripDetailStore: ObservableObject {
    let trip: Trip

    @Published private(set) var days: [TripDayRecord] = []
    @Published private(set) var places: [PlaceRecord] = []
    @Published private(set) var reservations: [ReservationRecord] = []
    @Published private(set) var expenses: [ExpenseRecord] = []
    @Published private(set) var expenseSplits: [ExpenseSplitRecord] = []
    @Published private(set) var settlements: [SettlementRecord] = []
    @Published private(set) var members: [TripMemberProfile] = []
    @Published private(set) var checklist: [ChecklistRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(trip: Trip, client: SupabaseClient = WandererSupabase.client) {
        self.trip = trip
        self.client = client
    }

    var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    var expensesByCategory: [(ExpenseCategory, Double)] {
        ExpenseCategory.allCases.compactMap { category in
            let total = expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
            return total > 0 ? (category, total) : nil
        }
    }

    var memberBalances: [MemberBalance] {
        let expenseModels = expenses.map { expense -> SplitMathExpense in
            let splits = expenseSplits.filter { $0.expenseId == expense.id }
            let splitMap: [UUID: Double]
            if splits.isEmpty {
                let participants = expense.splitWith.isEmpty
                    ? [expense.paidBy].compactMap { $0 }
                    : expense.splitWith
                let share = expense.amount / Double(max(1, participants.count))
                splitMap = Dictionary(uniqueKeysWithValues: participants.map { ($0, share) })
            } else {
                splitMap = Dictionary(uniqueKeysWithValues: splits.map { ($0.userId, $0.amount) })
            }
            return SplitMathExpense(payer: expense.paidBy, amount: expense.amount, splits: splitMap)
        }

        let settlementModels = settlements.map {
            SplitMathSettlement(from: $0.fromUser, to: $0.toUser, amount: $0.amount)
        }

        let nets = SplitMath.balances(
            members: members.map(\.userId),
            expenses: expenseModels,
            settlements: settlementModels
        )

        return members
            .map { MemberBalance(member: $0, net: nets[$0.userId] ?? 0) }
            .sorted { $0.net > $1.net }
    }

    var currentUserId: UUID? {
        WandererSupabase.client.auth.currentSession?.user.id
    }

    func places(for dayID: UUID?) -> [PlaceRecord] {
        places
            .filter { $0.dayId == dayID }
            .sorted { $0.position < $1.position }
    }

    var unassignedPlaces: [PlaceRecord] {
        places(for: nil)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let tripID = trip.id.uuidString
        async let daysTask: [TripDayRecord] = client.from("trip_days")
            .select()
            .eq("trip_id", value: tripID)
            .order("day_index", ascending: true)
            .execute()
            .value

        async let placesTask: [PlaceRecord] = client.from("places")
            .select()
            .eq("trip_id", value: tripID)
            .order("position", ascending: true)
            .execute()
            .value

        async let reservationsTask: [ReservationRecord] = client.from("reservations")
            .select()
            .eq("trip_id", value: tripID)
            .order("start_at", ascending: true)
            .execute()
            .value

        async let expensesTask: [ExpenseRecord] = client.from("expenses")
            .select()
            .eq("trip_id", value: tripID)
            .order("spent_at", ascending: false)
            .execute()
            .value

        async let checklistTask: [ChecklistRecord] = client.from("checklist_items")
            .select()
            .eq("trip_id", value: tripID)
            .order("position", ascending: true)
            .execute()
            .value

        async let membersTask: [TripMemberProfile] = client.from("trip_members")
            .select("user_id,role,profiles!trip_members_user_id_fkey(id,display_name,email)")
            .eq("trip_id", value: tripID)
            .execute()
            .value

        async let splitsTask: [ExpenseSplitRecord] = client.from("expense_splits")
            .select()
            .eq("trip_id", value: tripID)
            .execute()
            .value

        async let settlementsTask: [SettlementRecord] = client.from("settlements")
            .select()
            .eq("trip_id", value: tripID)
            .order("settled_at", ascending: false)
            .execute()
            .value

        do {
            let (loadedDays, loadedPlaces, loadedReservations, loadedExpenses, loadedChecklist, loadedMembers, loadedSplits, loadedSettlements) =
                try await (daysTask, placesTask, reservationsTask, expensesTask, checklistTask, membersTask, splitsTask, settlementsTask)
            days = loadedDays
            places = loadedPlaces
            reservations = loadedReservations
            expenses = loadedExpenses
            checklist = loadedChecklist
            members = loadedMembers
            expenseSplits = loadedSplits
            settlements = loadedSettlements
        } catch {
            errorMessage = "Couldn't load this trip: \(error.localizedDescription)"
        }
    }

    // MARK: - Places

    func addPlace(
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        category: PlaceCategory,
        dayID: UUID?,
        website: String? = nil,
        phone: String? = nil
    ) async {
        do {
            let session = try await client.auth.session
            let position = (places(for: dayID).map(\.position).max() ?? -1) + 1
            let payload = NewPlacePayload(
                tripId: trip.id.uuidString,
                dayId: dayID?.uuidString,
                name: name,
                address: address,
                lat: latitude,
                lng: longitude,
                category: category.rawValue,
                website: website,
                phone: phone,
                position: position,
                createdBy: session.user.id.uuidString
            )
            try await client.from("places").insert(payload).execute()
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't add that place: \(error.localizedDescription)"
        }
    }

    func updatePlace(_ place: PlaceRecord, name: String, notes: String?, category: PlaceCategory) async {
        do {
            let payload = PlaceUpdatePayload(name: name, notes: notes, category: category.rawValue)
            try await client.from("places").update(payload).eq("id", value: place.id.uuidString).execute()
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't save that place: \(error.localizedDescription)"
        }
    }

    func deletePlace(_ place: PlaceRecord) async {
        do {
            try await client.from("places").delete().eq("id", value: place.id.uuidString).execute()
            places.removeAll { $0.id == place.id }
        } catch {
            errorMessage = "Couldn't remove that place: \(error.localizedDescription)"
        }
    }

    func movePlaces(in dayID: UUID?, fromOffsets: IndexSet, toOffset: Int) async {
        var items = places(for: dayID)
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        places = places.filter { $0.dayId != dayID } + items

        for (index, item) in items.enumerated() where item.position != index {
            do {
                try await client.from("places")
                    .update(["position": index])
                    .eq("id", value: item.id.uuidString)
                    .execute()
            } catch {
                errorMessage = "Couldn't reorder places: \(error.localizedDescription)"
                return
            }
        }
        await reloadPlaces()
    }

    func optimizeRoute(for dayID: UUID?) async {
        let items = places(for: dayID)
        guard items.count > 1 else { return }

        let withCoordinates = items.filter { $0.coordinate != nil }
        guard withCoordinates.count > 1 else { return }

        var remaining = withCoordinates
        var ordered: [PlaceRecord] = []
        var current = remaining.removeFirst()
        ordered.append(current)

        while !remaining.isEmpty {
            guard let nearestIndex = remaining.indices.min(by: {
                distance(current, remaining[$0]) < distance(current, remaining[$1])
            }) else { break }
            current = remaining.remove(at: nearestIndex)
            ordered.append(current)
        }

        let withoutCoordinates = items.filter { $0.coordinate == nil }
        let finalOrder = ordered + withoutCoordinates

        do {
            for (index, place) in finalOrder.enumerated() {
                try await client.from("places")
                    .update(["position": index])
                    .eq("id", value: place.id.uuidString)
                    .execute()
            }
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't optimize the route: \(error.localizedDescription)"
        }
    }

    private func distance(_ lhs: PlaceRecord, _ rhs: PlaceRecord) -> Double {
        guard let a = lhs.coordinate, let b = rhs.coordinate else {
            return .greatestFiniteMagnitude
        }
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    func assign(_ place: PlaceRecord, to dayID: UUID?) async {
        do {
            let position = (places(for: dayID).map(\.position).max() ?? -1) + 1
            let payload = PlaceDayPayload(dayId: dayID?.uuidString, position: position)
            try await client.from("places")
                .update(payload)
                .eq("id", value: place.id.uuidString)
                .execute()
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't move that place: \(error.localizedDescription)"
        }
    }

    private func reloadPlaces() async {
        do {
            places = try await client.from("places")
                .select()
                .eq("trip_id", value: trip.id.uuidString)
                .order("position", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't refresh places: \(error.localizedDescription)"
        }
    }

    // MARK: - Days

    func updateDayNotes(_ day: TripDayRecord, notes: String) async {
        do {
            try await client.from("trip_days")
                .update(["notes": notes])
                .eq("id", value: day.id.uuidString)
                .execute()
            if let index = days.firstIndex(where: { $0.id == day.id }) {
                days[index].notes = notes.isEmpty ? nil : notes
            }
        } catch {
            errorMessage = "Couldn't save the day note: \(error.localizedDescription)"
        }
    }

    // MARK: - Reservations

    func addReservation(
        type: ReservationType,
        title: String,
        provider: String?,
        confirmationCode: String?,
        startAt: Date?,
        endAt: Date?,
        startLocation: String?,
        endLocation: String?,
        cost: Double?,
        currency: String,
        notes: String?
    ) async {
        do {
            let payload = NewReservationPayload(
                tripId: trip.id.uuidString,
                type: type.rawValue,
                title: title,
                provider: provider,
                confirmationCode: confirmationCode,
                startAt: Self.timestamp(startAt),
                endAt: Self.timestamp(endAt),
                startLocation: startLocation,
                endLocation: endLocation,
                cost: cost,
                currency: currency,
                notes: notes
            )
            try await client.from("reservations").insert(payload).execute()
            await reloadReservations()
        } catch {
            errorMessage = "Couldn't add that reservation: \(error.localizedDescription)"
        }
    }

    func deleteReservation(_ reservation: ReservationRecord) async {
        do {
            try await client.from("reservations").delete().eq("id", value: reservation.id.uuidString).execute()
            reservations.removeAll { $0.id == reservation.id }
        } catch {
            errorMessage = "Couldn't remove that reservation: \(error.localizedDescription)"
        }
    }

    private func reloadReservations() async {
        do {
            reservations = try await client.from("reservations")
                .select()
                .eq("trip_id", value: trip.id.uuidString)
                .order("start_at", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't refresh reservations: \(error.localizedDescription)"
        }
    }

    // MARK: - Expenses

    func addExpense(
        title: String,
        amount: Double,
        currency: String,
        category: ExpenseCategory,
        paidBy: UUID?,
        splitWith: [UUID],
        spentAt: Date,
        notes: String?
    ) async {
        let participants = splitWith.isEmpty
            ? members.map(\.userId)
            : splitWith
        let share = amount / Double(max(1, participants.count))
        var splitAmounts: [UUID: Double] = [:]
        for participant in participants {
            splitAmounts[participant] = share
        }
        await addExpense(
            title: title,
            amount: amount,
            currency: currency,
            category: category,
            paidBy: paidBy ?? currentUserId,
            splitMode: .equal,
            splitAmounts: splitAmounts,
            spentAt: spentAt,
            notes: notes
        )
    }

    func addExpense(
        title: String,
        amount: Double,
        currency: String,
        category: ExpenseCategory,
        paidBy: UUID?,
        splitMode: ExpenseSplitMode,
        splitAmounts: [UUID: Double],
        spentAt: Date,
        notes: String?
    ) async {
        do {
            let participants = splitAmounts.keys.map { $0.uuidString }
            let payload = NewExpensePayload(
                tripId: trip.id.uuidString,
                title: title,
                amount: amount,
                currency: currency,
                category: category.rawValue,
                paidBy: paidBy?.uuidString,
                splitWith: participants,
                splitMode: splitMode.rawValue,
                spentAt: Self.dayString(spentAt),
                notes: notes
            )
            let inserted: ExpenseRecord = try await client.from("expenses")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            let splitPayloads = splitAmounts.map { userId, share in
                NewExpenseSplitPayload(
                    tripId: trip.id.uuidString,
                    expenseId: inserted.id.uuidString,
                    userId: userId.uuidString,
                    amount: share
                )
            }
            if !splitPayloads.isEmpty {
                try await client.from("expense_splits").insert(splitPayloads).execute()
            }

            await reloadExpenses()
            await reloadSplits()
        } catch {
            errorMessage = "Couldn't add that expense: \(error.localizedDescription)"
        }
    }

    func deleteExpense(_ expense: ExpenseRecord) async {
        do {
            try await client.from("expenses").delete().eq("id", value: expense.id.uuidString).execute()
            expenses.removeAll { $0.id == expense.id }
            expenseSplits.removeAll { $0.expenseId == expense.id }
        } catch {
            errorMessage = "Couldn't remove that expense: \(error.localizedDescription)"
        }
    }

    func settleUp(from: UUID, to: UUID, amount: Double, currency: String, note: String?) async {
        do {
            let payload = NewSettlementPayload(
                tripId: trip.id.uuidString,
                fromUser: from.uuidString,
                toUser: to.uuidString,
                amount: amount,
                currency: currency,
                settledAt: Self.dayString(Date()),
                note: note,
                createdBy: currentUserId?.uuidString
            )
            try await client.from("settlements").insert(payload).execute()
            await reloadSettlements()
        } catch {
            errorMessage = "Couldn't record that payment: \(error.localizedDescription)"
        }
    }

    func deleteSettlement(_ settlement: SettlementRecord) async {
        do {
            try await client.from("settlements").delete().eq("id", value: settlement.id.uuidString).execute()
            settlements.removeAll { $0.id == settlement.id }
        } catch {
            errorMessage = "Couldn't remove that payment: \(error.localizedDescription)"
        }
    }

    private func reloadExpenses() async {
        do {
            expenses = try await client.from("expenses")
                .select()
                .eq("trip_id", value: trip.id.uuidString)
                .order("spent_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't refresh expenses: \(error.localizedDescription)"
        }
    }

    private func reloadSplits() async {
        do {
            expenseSplits = try await client.from("expense_splits")
                .select()
                .eq("trip_id", value: trip.id.uuidString)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't refresh the split details: \(error.localizedDescription)"
        }
    }

    private func reloadSettlements() async {
        do {
            settlements = try await client.from("settlements")
                .select()
                .eq("trip_id", value: trip.id.uuidString)
                .order("settled_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't refresh the payments: \(error.localizedDescription)"
        }
    }

    // MARK: - Checklist

    func addChecklistItem(title: String) async {
        do {
            let position = (checklist.map(\.position).max() ?? -1) + 1
            let payload = NewChecklistPayload(
                tripId: trip.id.uuidString,
                title: title,
                position: position
            )
            try await client.from("checklist_items").insert(payload).execute()
            await reloadChecklist()
        } catch {
            errorMessage = "Couldn't add that item: \(error.localizedDescription)"
        }
    }

    func toggleChecklist(_ item: ChecklistRecord) async {
        do {
            try await client.from("checklist_items")
                .update(["is_checked": !item.isChecked])
                .eq("id", value: item.id.uuidString)
                .execute()
            await reloadChecklist()
        } catch {
            errorMessage = "Couldn't update that item: \(error.localizedDescription)"
        }
    }

    func deleteChecklistItem(_ item: ChecklistRecord) async {
        do {
            try await client.from("checklist_items").delete().eq("id", value: item.id.uuidString).execute()
            checklist.removeAll { $0.id == item.id }
        } catch {
            errorMessage = "Couldn't remove that item: \(error.localizedDescription)"
        }
    }

    private func reloadChecklist() async {
        do {
            checklist = try await client.from("checklist_items")
                .select()
                .eq("trip_id", value: trip.id.uuidString)
                .order("position", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't refresh the checklist: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private static func timestamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Payloads

private struct NewPlacePayload: Encodable {
    let tripId: String
    let dayId: String?
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let category: String
    let website: String?
    let phone: String?
    let position: Int
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case dayId = "day_id"
        case name, address, lat, lng, category, website, phone, position
        case createdBy = "created_by"
    }
}

private struct PlaceUpdatePayload: Encodable {
    let name: String
    let notes: String?
    let category: String
}

private struct PlaceDayPayload: Encodable {
    let dayId: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case dayId = "day_id"
        case position
    }
}

private struct NewReservationPayload: Encodable {
    let tripId: String
    let type: String
    let title: String
    let provider: String?
    let confirmationCode: String?
    let startAt: String?
    let endAt: String?
    let startLocation: String?
    let endLocation: String?
    let cost: Double?
    let currency: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case type, title, provider, cost, currency, notes
        case confirmationCode = "confirmation_code"
        case startAt = "start_at"
        case endAt = "end_at"
        case startLocation = "start_location"
        case endLocation = "end_location"
    }
}

private struct NewExpensePayload: Encodable {
    let tripId: String
    let title: String
    let amount: Double
    let currency: String
    let category: String
    let paidBy: String?
    let splitWith: [String]
    let splitMode: String
    let spentAt: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case title, amount, currency, category, notes
        case paidBy = "paid_by"
        case splitWith = "split_with"
        case splitMode = "split_mode"
        case spentAt = "spent_at"
    }
}

private struct NewExpenseSplitPayload: Encodable {
    let tripId: String
    let expenseId: String
    let userId: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case expenseId = "expense_id"
        case userId = "user_id"
        case amount
    }
}

private struct NewSettlementPayload: Encodable {
    let tripId: String
    let fromUser: String
    let toUser: String
    let amount: Double
    let currency: String
    let settledAt: String
    let note: String?
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case fromUser = "from_user"
        case toUser = "to_user"
        case amount, currency, note
        case settledAt = "settled_at"
        case createdBy = "created_by"
    }
}

private struct NewChecklistPayload: Encodable {
    let tripId: String
    let title: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case title, position
    }
}
