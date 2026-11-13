import Foundation

/// Everything inside one trip, loaded from the Wanderer API.
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
    @Published private(set) var lists: [TripListRecord] = []
    /// What other people see: the shared rows exactly as stored.
    @Published private(set) var personal: PersonalLayerRecord = .empty
    /// Keyed by reservation id; missing when no live status is available.
    @Published private(set) var flightStatuses: [String: FlightLookupEnvelope] = [:]
    @Published private(set) var flightAttribution: String?
    @Published private(set) var flightBudget: FlightBudget?
    @Published private(set) var isLoading = false
    @Published private(set) var cloudUserId: UUID?
    @Published private(set) var isChangingDays = false
    @Published var selectedDayHint: UUID?
    @Published var errorMessage: String?

    /// Set only by tests, to run the store against an isolated local server.
    private let apiOverride: WandererAPI?

    init(trip: Trip, api: WandererAPI? = nil) {
        self.trip = trip
        self.apiOverride = api
    }

    // MARK: - Undo / redo

    /// One reversible planner edit.
    struct PlannerChange {
        let label: String
        let undo: @MainActor () async -> Void
        let redo: @MainActor () async -> Void
    }

    @Published private(set) var undoStack: [PlannerChange] = []
    @Published private(set) var redoStack: [PlannerChange] = []
    /// The latest change, for the "Undo" toast. Cleared when undone.
    @Published private(set) var lastChange: PlannerChange?
    @Published private(set) var changeCount = 0
    private var isReplaying = false
    /// A removed place comes back with a new id; older undo steps follow
    /// this map so they still find it.
    private var idAliases: [UUID: UUID] = [:]
    static let undoLimit = 30

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func resolve(_ id: UUID) -> UUID {
        var current = id
        var hops = 0
        while let next = idAliases[current], hops < 64 {
            current = next
            hops += 1
        }
        return current
    }

    private func record(_ change: PlannerChange) {
        guard !isReplaying else { return }
        undoStack.append(change)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
        lastChange = change
        changeCount += 1
    }

    func undo() async {
        guard let change = undoStack.popLast() else { return }
        isReplaying = true
        await change.undo()
        isReplaying = false
        redoStack.append(change)
        lastChange = nil
        changeCount += 1
    }

    func redo() async {
        guard let change = redoStack.popLast() else { return }
        isReplaying = true
        await change.redo()
        isReplaying = false
        undoStack.append(change)
        lastChange = nil
        changeCount += 1
    }

    func dismissLastChange() {
        lastChange = nil
    }

    /// Puts the given places, in order, at positions 0... within their day.
    private func applyOrder(_ ids: [UUID]) async {
        guard let cloud else { return }
        for (index, original) in ids.enumerated() {
            let id = resolve(original)
            _ = try? await cloud.updatePlace(tripID: trip.id, placeID: id, body: ["position": .integer(index)])
        }
        await reloadPlaces()
    }

    /// Re-creates a removed place with every field it had, and returns its new id.
    private func recreate(_ place: PlaceRecord) async -> UUID? {
        guard let cloud else { return nil }
        let body: [String: JSONValue] = [
            "day_id": .optional(place.dayId.map(resolve)),
            "list_id": .optional(place.listId),
            "name": .string(place.name),
            "address": .optional(place.address),
            "lat": .optional(place.lat),
            "lng": .optional(place.lng),
            "category": .string(place.category.rawValue),
            "notes": .optional(place.notes),
            "website": .optional(place.website),
            "phone": .optional(place.phone),
            "price_level": .optional(place.priceLevel),
            "rating": .optional(place.rating),
            "photo_url": .optional(place.photoUrl),
            "start_time": .optional(place.startTime),
            "end_time": .optional(place.endTime),
            "position": .integer(place.position)
        ]
        guard let created = try? await cloud.addPlace(tripID: trip.id, body: body) else { return nil }
        if let visitedAt = place.visitedAt {
            _ = try? await cloud.setPlaceVisited(tripID: trip.id, placeID: created.id, visitedAt: visitedAt)
        }
        idAliases[resolve(place.id)] = created.id
        return created.id
    }

    /// Guest trips live on the device and go through the local server; signed
    /// in, the same calls go to the Worker.
    private var cloud: WandererAPI? {
        if let apiOverride { return apiOverride }
        return LocalTrips.isActive ? LocalTripServer.api() : CloudSession.shared.api
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

    var currentUserId: UUID? { cloudUserId }

    // MARK: - Personal layer

    private static func personalKey(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private func overrideMap() -> [String: PersonalOverrideRecord] {
        Dictionary(personal.overrides.map { ($0.itemId.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Shared places with this member's replacements applied, plus the places
    /// only they added. Everyone else's view is untouched.
    var visiblePlaces: [PlaceRecord] {
        let overrides = overrideMap()
        let hidden = Set(personal.overrides.filter(\.hidden).map { $0.itemId.lowercased() })
        let shared = places
            .filter { !hidden.contains(Self.personalKey($0.id)) }
            .map { apply(overrides[Self.personalKey($0.id)], to: $0) }
        return shared + personal.privatePlaces
    }

    /// Shared reservations with replacements and this member's private
    /// bookings. Used everywhere the planner lists bookings.
    var visibleReservations: [ReservationRecord] {
        let overrides = overrideMap()
        let hidden = Set(personal.overrides.filter(\.hidden).map { $0.itemId.lowercased() })
        let shared = reservations
            .filter { !hidden.contains(Self.personalKey($0.id)) }
            .map { apply(overrides[Self.personalKey($0.id)], to: $0) }
        return shared + personal.privateReservations
    }

    func isPrivate(_ place: PlaceRecord) -> Bool {
        personal.privatePlaces.contains { $0.id == place.id }
    }

    func isPrivate(_ reservation: ReservationRecord) -> Bool {
        personal.privateReservations.contains { $0.id == reservation.id }
    }

    /// The active replacement for a shared row, if the member made one.
    func personalOverride(for id: UUID) -> PersonalOverrideRecord? {
        let key = Self.personalKey(id)
        return personal.overrides.first { $0.itemId.lowercased() == key }
    }

    func flightStatus(for reservationID: UUID) -> FlightStatusRecord? {
        flightStatuses[Self.personalKey(reservationID)]?.flight
    }

    private func apply(_ override: PersonalOverrideRecord?, to place: PlaceRecord) -> PlaceRecord {
        guard let data = override?.data, !data.isEmpty else { return place }
        var updated = place
        if let value = data["name"]?.stringValue { updated.name = value }
        if let value = data["address"] { updated.address = value.stringValue }
        if let value = data["category"]?.stringValue.flatMap(PlaceCategory.init(rawValue:)) {
            updated.category = value
        }
        if let value = data["notes"] { updated.notes = value.stringValue }
        if let value = data["website"] { updated.website = value.stringValue }
        if let value = data["phone"] { updated.phone = value.stringValue }
        if let value = data["start_time"] { updated.startTime = value.stringValue }
        if let value = data["end_time"] { updated.endTime = value.stringValue }
        return updated
    }

    private func apply(_ override: PersonalOverrideRecord?, to reservation: ReservationRecord) -> ReservationRecord {
        guard let data = override?.data, !data.isEmpty else { return reservation }
        var updated = reservation
        if let value = data["title"]?.stringValue { updated.title = value }
        if let value = data["provider"] { updated.provider = value.stringValue }
        if let value = data["confirmation_code"] { updated.confirmationCode = value.stringValue }
        if let value = data["start_at"] { updated.startAt = value.stringValue }
        if let value = data["end_at"] { updated.endAt = value.stringValue }
        if let value = data["start_location"] { updated.startLocation = value.stringValue }
        if let value = data["end_location"] { updated.endLocation = value.stringValue }
        if let value = data["notes"] { updated.notes = value.stringValue }
        if let value = data["cost"]?.doubleValue { updated.cost = value }
        if let value = data["currency"]?.stringValue { updated.currency = value }
        return updated
    }

    func hideForMe(_ place: PlaceRecord) async {
        await setOverride(for: place, hidden: true, data: [:])
    }

    func hideReservationForMe(_ reservation: ReservationRecord) async {
        guard let cloud else { return }
        do {
            _ = try await cloud.setPersonalOverride(
                tripID: trip.id,
                itemType: "reservation",
                itemID: reservation.id,
                hidden: true,
                data: [:]
            )
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't hide that booking: \(error.localizedDescription)"
        }
    }

    func restoreReservationForMe(_ reservation: ReservationRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.clearPersonalOverride(tripID: trip.id, itemType: "reservation", itemID: reservation.id)
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't restore that booking: \(error.localizedDescription)"
        }
    }

    func restoreForMe(_ place: PlaceRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.clearPersonalOverride(tripID: trip.id, itemType: "place", itemID: place.id)
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't restore that stop: \(error.localizedDescription)"
        }
    }

    /// Saves a replacement that only this member sees.
    func updateForMe(_ place: PlaceRecord, name: String, notes: String?, category: PlaceCategory) async {
        var data: [String: JSONValue] = ["name": .string(name), "category": .string(category.rawValue)]
        data["notes"] = .optional(notes)
        await setOverride(for: place, hidden: false, data: data)
    }

    func setOverride(for place: PlaceRecord, hidden: Bool, data: [String: JSONValue]) async {
        guard let cloud else { return }
        do {
            _ = try await cloud.setPersonalOverride(
                tripID: trip.id,
                itemType: "place",
                itemID: place.id,
                hidden: hidden,
                data: data
            )
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't update your private view: \(error.localizedDescription)"
        }
    }

    /// A stop only this member sees. Private stops can sit on a day like any
    /// other stop but never appear in another member's itinerary.
    func addPrivatePlace(
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        category: PlaceCategory,
        dayID: UUID?
    ) async {
        guard let cloud else { return }
        do {
            _ = try await cloud.addPrivatePlace(tripID: trip.id, body: [
                "name": .string(name),
                "address": .optional(address),
                "lat": .optional(latitude),
                "lng": .optional(longitude),
                "category": .string(category.rawValue),
                "day_id": .optional(dayID),
                "position": .integer(places(for: dayID).count)
            ])
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't add your private stop: \(error.localizedDescription)"
        }
    }

    func deletePrivatePlace(_ place: PlaceRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.deletePrivatePlace(tripID: trip.id, placeID: place.id)
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't remove that private stop: \(error.localizedDescription)"
        }
    }

    func addPrivateReservation(
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
        notes: String?,
        flightNumber: String?,
        flightDate: String?
    ) async {
        guard let cloud else { return }
        var metadata: [String: JSONValue] = [:]
        if let flightNumber { metadata["flight_number"] = .string(flightNumber) }
        if let flightDate { metadata["flight_date"] = .string(flightDate) }
        do {
            _ = try await cloud.addPrivateReservation(tripID: trip.id, body: [
                "type": .string(type.rawValue),
                "title": .string(title),
                "provider": .optional(provider),
                "confirmation_code": .optional(confirmationCode),
                "start_at": .optional(Self.timestamp(startAt)),
                "end_at": .optional(Self.timestamp(endAt)),
                "start_location": .optional(startLocation),
                "end_location": .optional(endLocation),
                "cost": .optional(cost),
                "currency": .string(currency),
                "notes": .optional(notes),
                "metadata": .object(metadata)
            ])
            await reloadPersonal()
            await refreshFlights()
        } catch {
            errorMessage = "Couldn't add your private booking: \(error.localizedDescription)"
        }
    }

    func deletePrivateReservation(_ reservation: ReservationRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.deletePrivateReservation(tripID: trip.id, reservationID: reservation.id)
            await reloadPersonal()
        } catch {
            errorMessage = "Couldn't remove that private booking: \(error.localizedDescription)"
        }
    }

    private func reloadPersonal() async {
        guard let cloud else { return }
        if let loaded = try? await cloud.personal(tripID: trip.id) {
            personal = loaded
        }
    }

    /// Quietly re-reads the collaborative parts of the trip. Used by the
    /// planner's 30-second refresh and pull-to-refresh, so a tripmate's edit
    /// appears without closing and reopening the trip.
    func refreshCollaboration() async {
        guard let cloud else { return }
        async let daysTask = try? cloud.days(tripID: trip.id)
        async let placesTask = try? cloud.places(tripID: trip.id)
        async let reservationsTask = try? cloud.reservations(tripID: trip.id)
        async let listsTask = try? cloud.lists(tripID: trip.id)
        async let personalTask = try? cloud.personal(tripID: trip.id)

        if let loaded = await daysTask { days = loaded }
        if let loaded = await placesTask { places = loaded }
        if let loaded = await reservationsTask { reservations = loaded }
        if let loaded = await listsTask { lists = loaded }
        if let loaded = await personalTask { personal = loaded }
    }

    /// Pulls live status for this trip's flights. Failure is silent: the
    /// itinerary still works without it.
    func refreshFlights() async {
        guard let cloud else { return }
        guard reservations.contains(where: { $0.type == .flight })
            || personal.privateReservations.contains(where: { $0.type == .flight }) else { return }
        if let envelope = try? await cloud.tripFlights(tripID: trip.id) {
            flightStatuses = envelope.flights
            flightAttribution = envelope.attribution
            flightBudget = envelope.budget
            FlightAlerts.process(tripTitle: trip.title, statuses: envelope.flights)
        }
    }

    func places(for dayID: UUID?) -> [PlaceRecord] {
        visiblePlaces
            .filter { $0.dayId == dayID }
            .sorted { $0.position < $1.position }
    }

    var unassignedPlaces: [PlaceRecord] {
        places(for: nil)
    }

    /// Total recorded cost for a stop, from expenses tagged with its id.
    func cost(for place: PlaceRecord) -> Double {
        expenses
            .filter { $0.placeId == place.id }
            .reduce(0) { $0 + $1.amount }
    }

    /// Unscheduled places grouped by list, ordered by list position. Loose
    /// places (no list) come last.
    var unscheduledGroups: [(list: TripListRecord?, places: [PlaceRecord])] {
        let loose = unassignedPlaces
        var groups = lists
            .sorted { $0.position < $1.position }
            .map { list in
                (list: list as TripListRecord?, places: loose.filter { $0.listId == list.id })
            }
        let withoutList = loose.filter { $0.listId == nil }
        if !withoutList.isEmpty {
            groups.append((list: nil, places: withoutList))
        }
        return groups
    }

    var visitedPlaces: [PlaceRecord] {
        visiblePlaces.filter(\.isVisited).sorted { ($0.visitedAt ?? "") < ($1.visitedAt ?? "") }
    }

    // MARK: - Load

    func load() async {
        guard let cloud else {
            errorMessage = "The Wanderer server is not configured for this build."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let daysTask = cloud.days(tripID: trip.id)
            async let placesTask = cloud.places(tripID: trip.id)
            async let reservationsTask = cloud.reservations(tripID: trip.id)
            async let expensesTask = cloud.expenses(tripID: trip.id)
            async let checklistTask = cloud.checklist(tripID: trip.id)
            async let membersTask = cloud.members(tripID: trip.id)
            async let splitsTask = cloud.expenseSplits(tripID: trip.id)
            async let settlementsTask = cloud.settlements(tripID: trip.id)
            async let listsTask = cloud.lists(tripID: trip.id)
            // The personal layer is optional: guest trips and older servers
            // simply have none, and that must not fail the whole load.
            async let personalTask = try? cloud.personal(tripID: trip.id)

            let (loadedDays, loadedPlaces, loadedReservations, loadedExpenses, loadedChecklist, loadedMembers, loadedSplits, loadedSettlements, loadedLists, loadedPersonal) =
                try await (daysTask, placesTask, reservationsTask, expensesTask, checklistTask, membersTask, splitsTask, settlementsTask, listsTask, personalTask)

            days = loadedDays
            places = loadedPlaces
            reservations = loadedReservations
            expenses = loadedExpenses
            checklist = loadedChecklist
            members = loadedMembers
            expenseSplits = loadedSplits
            settlements = loadedSettlements
            lists = loadedLists
            personal = loadedPersonal ?? .empty
            cloudUserId = try? await cloud.profile().id
            errorMessage = nil

            // Live flight status is a background nicety; never block opening
            // a trip on a paid lookup.
            Task { await refreshFlights() }
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
        guard let cloud else { return }
        do {
            let position = (places(for: dayID).map(\.position).max() ?? -1) + 1
            _ = try await cloud.addPlace(tripID: trip.id, body: [
                "day_id": .optional(dayID),
                "name": .string(name),
                "address": .optional(address),
                "lat": .optional(latitude),
                "lng": .optional(longitude),
                "category": .string(category.rawValue),
                "website": .optional(website),
                "phone": .optional(phone),
                "position": .integer(position)
            ])
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't add that place: \(error.localizedDescription)"
        }
    }

    func updatePlace(_ place: PlaceRecord, name: String, notes: String?, category: PlaceCategory) async {
        guard let cloud else { return }
        do {
            if isPrivate(place) {
                _ = try await cloud.updatePrivatePlace(tripID: trip.id, placeID: place.id, body: [
                    "name": .string(name),
                    "notes": .optional(notes),
                    "category": .string(category.rawValue)
                ])
                await reloadPersonal()
                return
            }
            _ = try await cloud.updatePlace(tripID: trip.id, placeID: place.id, body: [
                "name": .string(name),
                "notes": .optional(notes),
                "category": .string(category.rawValue)
            ])
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't save that place: \(error.localizedDescription)"
        }
    }

    func deletePlace(_ place: PlaceRecord) async {
        guard let cloud else { return }
        if isPrivate(place) {
            await deletePrivatePlace(place)
            return
        }
        do {
            try await cloud.deletePlace(tripID: trip.id, placeID: place.id)
            places.removeAll { $0.id == place.id }
            // Neighbours keep their order; the restored stop goes back to its slot.
            let snapshot = place
            let neighbours = places(for: place.dayId).map(\.id)
            record(PlannerChange(
                label: "Removed \(place.name)",
                undo: { [weak self] in
                    guard let self, let restored = await self.recreate(snapshot) else { return }
                    var order = neighbours.map(self.resolve)
                    order.insert(restored, at: min(max(0, snapshot.position), order.count))
                    await self.applyOrder(order)
                },
                redo: { [weak self] in
                    guard let self, let cloud = self.cloud else { return }
                    let current = self.resolve(snapshot.id)
                    try? await cloud.deletePlace(tripID: self.trip.id, placeID: current)
                    await self.reloadPlaces()
                }
            ))
        } catch {
            errorMessage = "Couldn't remove that place: \(error.localizedDescription)"
        }
    }

    func movePlaces(in dayID: UUID?, fromOffsets: IndexSet, toOffset: Int) async {
        var items = places(for: dayID)
        let before = items.map(\.id)
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let after = items.map(\.id)
        if before != after {
            record(PlannerChange(
                label: "Reordered stops",
                undo: { [weak self] in await self?.applyOrder(before) },
                redo: { [weak self] in await self?.applyOrder(after) }
            ))
        }
        places = places.filter { $0.dayId != dayID } + items
        guard let cloud else { return }

        for (index, item) in items.enumerated() where item.position != index {
            do {
                _ = try await cloud.updatePlace(
                    tripID: trip.id,
                    placeID: item.id,
                    body: ["position": .integer(index)]
                )
            } catch {
                errorMessage = "Couldn't reorder places: \(error.localizedDescription)"
                return
            }
        }
        await reloadPlaces()
    }

    func optimizeRoute(for dayID: UUID?) async {
        let items = places(for: dayID)
        guard items.count > 1, let cloud else { return }

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

        let finalOrder = ordered + items.filter { $0.coordinate == nil }
        let before = items.map(\.id)
        let after = finalOrder.map(\.id)
        if before != after {
            record(PlannerChange(
                label: "Optimized the route",
                undo: { [weak self] in await self?.applyOrder(before) },
                redo: { [weak self] in await self?.applyOrder(after) }
            ))
        }

        do {
            for (index, place) in finalOrder.enumerated() {
                _ = try await cloud.updatePlace(
                    tripID: trip.id,
                    placeID: place.id,
                    body: ["position": .integer(index)]
                )
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
        guard let cloud else { return }
        do {
            let position = (places(for: dayID).map(\.position).max() ?? -1) + 1
            let originalDay = place.dayId
            let originalOrder = places(for: originalDay).map(\.id)
            _ = try await cloud.updatePlace(tripID: trip.id, placeID: place.id, body: [
                "day_id": .optional(dayID),
                "position": .integer(position)
            ])
            await reloadPlaces()
            let placeID = place.id
            let dayName = dayID.flatMap { id in days.first { $0.id == id } }.map { "Day \($0.dayIndex + 1)" } ?? "Ideas"
            record(PlannerChange(
                label: "Moved \(place.name) to \(dayName)",
                undo: { [weak self] in
                    guard let self, let cloud = self.cloud else { return }
                    _ = try? await cloud.updatePlace(tripID: self.trip.id, placeID: self.resolve(placeID), body: [
                        "day_id": .optional(originalDay.map(self.resolve))
                    ])
                    await self.applyOrder(originalOrder)
                },
                redo: { [weak self] in
                    guard let self, let cloud = self.cloud else { return }
                    let end = (self.places(for: dayID).map(\.position).max() ?? -1) + 1
                    _ = try? await cloud.updatePlace(tripID: self.trip.id, placeID: self.resolve(placeID), body: [
                        "day_id": .optional(dayID), "position": .integer(end)
                    ])
                    await self.reloadPlaces()
                }
            ))
        } catch {
            errorMessage = "Couldn't move that place: \(error.localizedDescription)"
        }
    }

    func setVisited(_ place: PlaceRecord, visited: Bool) async {
        guard let cloud else { return }
        let stamp = visited ? Self.timestamp(Date()) : nil
        do {
            _ = try await cloud.setPlaceVisited(tripID: trip.id, placeID: place.id, visitedAt: stamp)
            await reloadPlaces()
            let previous = place.visitedAt
            let placeID = place.id
            record(PlannerChange(
                label: visited ? "Marked \(place.name) visited" : "Unmarked \(place.name)",
                undo: { [weak self] in
                    guard let self, let cloud = self.cloud else { return }
                    _ = try? await cloud.setPlaceVisited(tripID: self.trip.id, placeID: self.resolve(placeID), visitedAt: previous)
                    await self.reloadPlaces()
                },
                redo: { [weak self] in
                    guard let self, let cloud = self.cloud else { return }
                    _ = try? await cloud.setPlaceVisited(tripID: self.trip.id, placeID: self.resolve(placeID), visitedAt: stamp)
                    await self.reloadPlaces()
                }
            ))
        } catch {
            errorMessage = "Couldn't update that place: \(error.localizedDescription)"
        }
    }

    func addCost(for place: PlaceRecord, amount: Double, currency: String) async {
        guard amount > 0, let cloud else { return }
        do {
            _ = try await cloud.addExpense(tripID: trip.id, body: [
                "title": .string(place.name),
                "amount": .number(amount),
                "currency": .string(currency),
                "category": .string(ExpenseCategory.activities.rawValue),
                "paid_by": .optional(currentUserId),
                "split_with": .array(currentUserId.map { [.string($0.uuidString)] } ?? []),
                "split_mode": .string(ExpenseSplitMode.equal.rawValue),
                "spent_at": .string(Self.dayString(Date())),
                "place_id": .optional(place.id),
                "splits": .array([])
            ])
            await reloadExpenses()
            await reloadSplits()
        } catch {
            errorMessage = "Couldn't add that cost: \(error.localizedDescription)"
        }
    }

    private func reloadPlaces() async {
        guard let cloud else { return }
        do {
            places = try await cloud.places(tripID: trip.id)
        } catch {
            errorMessage = "Couldn't refresh places: \(error.localizedDescription)"
        }
    }

    // MARK: - Lists

    func addList(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let cloud else { return }
        let position = (lists.map(\.position).max() ?? -1) + 1
        do {
            _ = try await cloud.addList(tripID: trip.id, title: trimmed, position: position)
            await reloadLists()
        } catch {
            errorMessage = "Couldn't create that list: \(error.localizedDescription)"
        }
    }

    func deleteList(_ list: TripListRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.deleteList(tripID: trip.id, listID: list.id)
            await reloadLists()
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't delete that list: \(error.localizedDescription)"
        }
    }

    func assign(_ place: PlaceRecord, toList listID: UUID?) async {
        guard let cloud else { return }
        do {
            _ = try await cloud.updatePlace(tripID: trip.id, placeID: place.id, body: ["list_id": .optional(listID)])
            await reloadPlaces()
        } catch {
            errorMessage = "Couldn't move that place: \(error.localizedDescription)"
        }
    }

    private func reloadLists() async {
        guard let cloud else { return }
        lists = (try? await cloud.lists(tripID: trip.id)) ?? lists
    }

    // MARK: - Days

    func updateDayNotes(_ day: TripDayRecord, notes: String) async {
        guard let cloud else { return }
        do {
            let updated = try await cloud.updateDay(
                tripID: trip.id,
                dayID: day.id,
                notes: notes.isEmpty ? nil : notes
            )
            if let index = days.firstIndex(where: { $0.id == day.id }) {
                days[index] = updated
            }
        } catch {
            errorMessage = "Couldn't save the day note: \(error.localizedDescription)"
        }
    }

    /// Inserts an empty day after `day`, shifting later days (and their dates)
    /// by one. The trip's end date grows with it so the range stays truthful.
    func insertDay(after day: TripDayRecord) async {
        guard !isChangingDays,
              let cloud,
              let newDate = Self.shifted(day.date, by: 1) else { return }
        isChangingDays = true
        defer { isChangingDays = false }

        do {
            let later = days
                .filter { $0.dayIndex > day.dayIndex }
                .sorted { $0.dayIndex > $1.dayIndex }
            for item in later {
                guard let date = Self.shifted(item.date, by: 1) else { continue }
                _ = try await cloud.updateDay(
                    tripID: trip.id,
                    dayID: item.id,
                    body: ["day_index": .integer(item.dayIndex + 1), "date": .string(date)]
                )
            }
            _ = try await cloud.addDay(tripID: trip.id, index: day.dayIndex + 1, date: newDate)
            await syncTripEndDate()
            await load()
            selectedDayHint = days.first(where: { $0.dayIndex == day.dayIndex + 1 })?.id
        } catch {
            errorMessage = "Couldn't insert a day: \(error.localizedDescription)"
        }
    }

    /// Removes a day. Its places become unscheduled rather than deleted.
    func deleteDay(_ day: TripDayRecord) async {
        guard !isChangingDays, days.count > 1, let cloud else { return }
        isChangingDays = true
        defer { isChangingDays = false }

        do {
            try await cloud.deleteDay(tripID: trip.id, dayID: day.id)
            for item in days.filter({ $0.dayIndex > day.dayIndex }).sorted(by: { $0.dayIndex < $1.dayIndex }) {
                guard let date = Self.shifted(item.date, by: -1) else { continue }
                _ = try await cloud.updateDay(
                    tripID: trip.id,
                    dayID: item.id,
                    body: ["day_index": .integer(item.dayIndex - 1), "date": .string(date)]
                )
            }
            await syncTripEndDate()
            await load()
        } catch {
            errorMessage = "Couldn't delete that day: \(error.localizedDescription)"
        }
    }

    private func syncTripEndDate() async {
        guard let cloud,
              let start = trip.startDate,
              let startDate = TripDayRecord.date(from: start) else { return }
        let count = max(1, (days.map(\.dayIndex).max() ?? 0) + 1)
        let end = Calendar.current.date(byAdding: .day, value: count - 1, to: startDate) ?? startDate
        _ = try? await cloud.updateTripEndDate(tripID: trip.id, endDate: Self.dayString(end))
    }

    private static func shifted(_ value: String?, by days: Int) -> String? {
        guard let date = TripDayRecord.date(from: value) else { return nil }
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) else { return nil }
        return dayString(shifted)
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
        notes: String?,
        flightNumber: String? = nil,
        flightDate: String? = nil
    ) async {
        guard let cloud else { return }
        var metadata: [String: JSONValue] = [:]
        if let flightNumber, !flightNumber.isEmpty { metadata["flight_number"] = .string(flightNumber) }
        if let flightDate, !flightDate.isEmpty { metadata["flight_date"] = .string(flightDate) }
        do {
            _ = try await cloud.addReservation(tripID: trip.id, body: [
                "type": .string(type.rawValue),
                "title": .string(title),
                "provider": .optional(provider),
                "confirmation_code": .optional(confirmationCode),
                "start_at": .optional(Self.timestamp(startAt)),
                "end_at": .optional(Self.timestamp(endAt)),
                "start_location": .optional(startLocation),
                "end_location": .optional(endLocation),
                "cost": .optional(cost),
                "currency": .string(currency),
                "notes": .optional(notes),
                "metadata": .object(metadata)
            ])
            await reloadReservations()
            await refreshFlights()
        } catch {
            errorMessage = "Couldn't add that reservation: \(error.localizedDescription)"
        }
    }

    func deleteReservation(_ reservation: ReservationRecord) async {
        guard let cloud else { return }
        if isPrivate(reservation) {
            await deletePrivateReservation(reservation)
            return
        }
        do {
            try await cloud.deleteReservation(tripID: trip.id, reservationID: reservation.id)
            reservations.removeAll { $0.id == reservation.id }
        } catch {
            errorMessage = "Couldn't remove that reservation: \(error.localizedDescription)"
        }
    }

    private func reloadReservations() async {
        guard let cloud else { return }
        do {
            reservations = try await cloud.reservations(tripID: trip.id)
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
        let participants = splitWith.isEmpty ? members.map(\.userId) : splitWith
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
        guard let cloud else { return }
        do {
            let participants = splitAmounts.keys.map { $0.uuidString }
            let splitRows: [JSONValue] = splitAmounts.map { userId, share in
                .object([
                    "user_id": .string(userId.uuidString),
                    "amount": .number(share)
                ])
            }
            _ = try await cloud.addExpense(tripID: trip.id, body: [
                "title": .string(title),
                "amount": .number(amount),
                "currency": .string(currency),
                "category": .string(category.rawValue),
                "paid_by": .optional(paidBy),
                "split_with": .array(participants.map { .string($0) }),
                "split_mode": .string(splitMode.rawValue),
                "spent_at": .string(Self.dayString(spentAt)),
                "notes": .optional(notes),
                "splits": .array(splitRows)
            ])
            await reloadExpenses()
            await reloadSplits()
        } catch {
            errorMessage = "Couldn't add that expense: \(error.localizedDescription)"
        }
    }

    func deleteExpense(_ expense: ExpenseRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.deleteExpense(tripID: trip.id, expenseID: expense.id)
            expenses.removeAll { $0.id == expense.id }
            expenseSplits.removeAll { $0.expenseId == expense.id }
        } catch {
            errorMessage = "Couldn't remove that expense: \(error.localizedDescription)"
        }
    }

    func settleUp(from: UUID, to: UUID, amount: Double, currency: String, note: String?) async {
        guard let cloud else { return }
        do {
            _ = try await cloud.addSettlement(tripID: trip.id, body: [
                "from_user": .string(from.uuidString),
                "to_user": .string(to.uuidString),
                "amount": .number(amount),
                "currency": .string(currency),
                "settled_at": .string(Self.dayString(Date())),
                "note": .optional(note)
            ])
            await reloadSettlements()
        } catch {
            errorMessage = "Couldn't record that payment: \(error.localizedDescription)"
        }
    }

    func deleteSettlement(_ settlement: SettlementRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.deleteSettlement(tripID: trip.id, settlementID: settlement.id)
            settlements.removeAll { $0.id == settlement.id }
        } catch {
            errorMessage = "Couldn't remove that payment: \(error.localizedDescription)"
        }
    }

    private func reloadExpenses() async {
        guard let cloud else { return }
        do {
            expenses = try await cloud.expenses(tripID: trip.id)
        } catch {
            errorMessage = "Couldn't refresh expenses: \(error.localizedDescription)"
        }
    }

    private func reloadSplits() async {
        guard let cloud else { return }
        do {
            expenseSplits = try await cloud.expenseSplits(tripID: trip.id)
        } catch {
            errorMessage = "Couldn't refresh the split details: \(error.localizedDescription)"
        }
    }

    private func reloadSettlements() async {
        guard let cloud else { return }
        do {
            settlements = try await cloud.settlements(tripID: trip.id)
        } catch {
            errorMessage = "Couldn't refresh the payments: \(error.localizedDescription)"
        }
    }

    // MARK: - Checklist

    func addChecklistItem(title: String) async {
        guard let cloud else { return }
        do {
            let position = (checklist.map(\.position).max() ?? -1) + 1
            _ = try await cloud.addChecklistItem(tripID: trip.id, title: title, position: position)
            await reloadChecklist()
        } catch {
            errorMessage = "Couldn't add that item: \(error.localizedDescription)"
        }
    }

    func toggleChecklist(_ item: ChecklistRecord) async {
        guard let cloud else { return }
        do {
            _ = try await cloud.updateChecklistItem(tripID: trip.id, itemID: item.id, isChecked: !item.isChecked)
            await reloadChecklist()
        } catch {
            errorMessage = "Couldn't update that item: \(error.localizedDescription)"
        }
    }

    func deleteChecklistItem(_ item: ChecklistRecord) async {
        guard let cloud else { return }
        do {
            try await cloud.deleteChecklistItem(tripID: trip.id, itemID: item.id)
            checklist.removeAll { $0.id == item.id }
        } catch {
            errorMessage = "Couldn't remove that item: \(error.localizedDescription)"
        }
    }

    private func reloadChecklist() async {
        guard let cloud else { return }
        do {
            checklist = try await cloud.checklist(tripID: trip.id)
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
