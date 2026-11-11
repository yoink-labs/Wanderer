import Foundation

/// Copies what a guest planned on the device into a trip on their account
/// after they sign in: days' notes, lists, places (kept on the same day
/// number and list), bookings, costs and the checklist. Costs are re-paid by
/// the signed-in person because the local "You" has no account.
enum GuestTripImporter {
    struct Summary: Equatable {
        var places = 0
        var reservations = 0
        var expenses = 0
        var checklist = 0
        var files = 0
    }

    static func copy(
        localTripID: UUID,
        into tripID: UUID,
        from local: WandererAPI = LocalTripServer.api(),
        to cloud: WandererAPI,
        payer: UUID?,
        localStore: LocalTripStore = LocalTripServer.shared.store
    ) async throws -> Summary {
        var summary = Summary()
        let localDays = try await local.days(tripID: localTripID)
        let remoteDays = try await cloud.days(tripID: tripID)
        var dayMap: [UUID: UUID] = [:]
        for day in localDays {
            guard let remote = remoteDays.first(where: { $0.dayIndex == day.dayIndex }) else { continue }
            dayMap[day.id] = remote.id
            if let notes = day.notes, !notes.isEmpty {
                _ = try await cloud.updateDay(tripID: tripID, dayID: remote.id, notes: notes)
            }
        }

        var listMap: [UUID: UUID] = [:]
        for list in try await local.lists(tripID: localTripID) {
            listMap[list.id] = try await cloud.addList(tripID: tripID, title: list.title, position: list.position).id
        }

        var placeMap: [UUID: UUID] = [:]
        for place in try await local.places(tripID: localTripID) {
            let created = try await cloud.addPlace(tripID: tripID, body: [
                "day_id": .optional(place.dayId.flatMap { dayMap[$0] }),
                "list_id": .optional(place.listId.flatMap { listMap[$0] }),
                "name": .string(place.name),
                "address": .optional(place.address),
                "lat": .optional(place.lat),
                "lng": .optional(place.lng),
                "category": .string(place.category.rawValue),
                "notes": .optional(place.notes),
                "website": .optional(place.website),
                "phone": .optional(place.phone),
                "start_time": .optional(place.startTime),
                "end_time": .optional(place.endTime),
                "position": .integer(place.position)
            ])
            if let visitedAt = place.visitedAt {
                _ = try await cloud.setPlaceVisited(tripID: tripID, placeID: created.id, visitedAt: visitedAt)
            }
            placeMap[place.id] = created.id
            summary.places += 1
        }

        for reservation in try await local.reservations(tripID: localTripID) {
            _ = try await cloud.addReservation(tripID: tripID, body: [
                "type": .string(reservation.type.rawValue),
                "title": .string(reservation.title),
                "provider": .optional(reservation.provider),
                "confirmation_code": .optional(reservation.confirmationCode),
                "start_at": .optional(reservation.startAt),
                "end_at": .optional(reservation.endAt),
                "start_location": .optional(reservation.startLocation),
                "end_location": .optional(reservation.endLocation),
                "cost": .optional(reservation.cost),
                "currency": .optional(reservation.currency),
                "notes": .optional(reservation.notes)
            ])
            summary.reservations += 1
        }

        for expense in try await local.expenses(tripID: localTripID) {
            _ = try await cloud.addExpense(tripID: tripID, body: [
                "title": .string(expense.title),
                "amount": .number(expense.amount),
                "currency": .string(expense.currency),
                "category": .string(expense.category.rawValue),
                "paid_by": .optional(payer),
                "split_with": .array(payer.map { [.string($0.uuidString)] } ?? []),
                "split_mode": .string(ExpenseSplitMode.equal.rawValue),
                "spent_at": .string(expense.spentAt),
                "notes": .optional(expense.notes),
                "place_id": .optional(expense.placeId.flatMap { placeMap[$0] }),
                "splits": .array([])
            ])
            summary.expenses += 1
        }

        for item in try await local.checklist(tripID: localTripID) {
            let created = try await cloud.addChecklistItem(tripID: tripID, title: item.title, position: item.position)
            if item.isChecked {
                _ = try await cloud.updateChecklistItem(tripID: tripID, itemID: created.id, isChecked: true)
            }
            summary.checklist += 1
        }
        // Files: read the stored bytes on the device and upload them.
        for file in (try? await local.attachments(tripID: localTripID)) ?? [] {
            guard let data = await localStore.fileData(storagePath: file.storagePath) else { continue }
            _ = try await cloud.uploadAttachment(
                tripID: tripID,
                data: data,
                fileName: file.name,
                mimeType: file.mimeType ?? "application/octet-stream"
            )
            summary.files += 1
        }
        return summary
    }
}
