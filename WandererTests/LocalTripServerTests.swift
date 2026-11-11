import XCTest
@testable import Wanderer

final class LocalTripServerTests: XCTestCase {
    private var directory: URL!
    private var api: WandererAPI!
    private let tripID = UUID()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        api = LocalTripServer.api(LocalTripServer(store: LocalTripStore(directory: directory)))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPlacesRoundTripThroughTheRealClient() async throws {
        let place = try await api.addPlace(tripID: tripID, body: [
            "name": .string("Kinkaku-ji"), "lat": .number(35.04), "lng": .number(135.73),
            "category": .string("sight"), "position": .integer(0)
        ])
        let visited = try await api.setPlaceVisited(tripID: tripID, placeID: place.id, visitedAt: "2026-11-10T09:00:00Z")
        XCTAssertTrue(visited.isVisited)
        let all = try await api.places(tripID: tripID)
        XCTAssertEqual(all.map(\.name), ["Kinkaku-ji"])
    }

    func testUppercaseIdsStillMatch() async throws {
        let place = try await api.addPlace(tripID: tripID, body: ["name": .string("A")])
        // The client sends uppercase UUIDs in paths; rows are stored lowercased.
        let renamed = try await api.updatePlace(tripID: tripID, placeID: place.id, body: ["name": .string("B")])
        XCTAssertEqual(renamed.name, "B")
    }

    func testDeletingADayUnschedulesItsPlaces() async throws {
        let day = try await api.addDay(tripID: tripID, index: 0, date: "2026-12-01")
        _ = try await api.addPlace(tripID: tripID, body: ["name": .string("Stop"), "day_id": .optional(day.id)])
        try await api.deleteDay(tripID: tripID, dayID: day.id)
        let places = try await api.places(tripID: tripID)
        XCTAssertNil(places.first?.dayId)
    }

    func testExpenseSplitsAreWrittenAndCascade() async throws {
        let member = UUID(uuidString: LocalTripStore.localUserID)!
        let expense = try await api.addExpense(tripID: tripID, body: [
            "title": .string("Dinner"), "amount": .number(40), "paid_by": .optional(member),
            "split_with": .array([.string(member.uuidString)]), "split_mode": .string("equal"),
            "splits": .array([.object(["user_id": .string(member.uuidString), "amount": .number(40)])])
        ])
        XCTAssertEqual(expense.amount, 40)
        let splits = try await api.expenseSplits(tripID: tripID)
        XCTAssertEqual(splits.count, 1)
        try await api.deleteExpense(tripID: tripID, expenseID: expense.id)
        let remaining = try await api.expenseSplits(tripID: tripID)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRowsSurviveANewServerInstance() async throws {
        _ = try await api.addChecklistItem(tripID: tripID, title: "Passport", position: 0)
        let reopened = LocalTripServer.api(LocalTripServer(store: LocalTripStore(directory: directory)))
        let items = try await reopened.checklist(tripID: tripID)
        XCTAssertEqual(items.map(\.title), ["Passport"])
        XCTAssertFalse(items[0].isChecked)
    }

    func testFilesAreStoredOnTheDeviceAndRemoved() async throws {
        let data = Data("boarding pass".utf8)
        let file = try await api.uploadAttachment(tripID: tripID, data: data, fileName: "../pass.pdf", mimeType: "application/pdf")
        XCTAssertEqual(file.name, "../pass.pdf")
        XCTAssertFalse(file.storagePath.contains(".."), "Stored path must not escape the files folder")
        XCTAssertEqual(file.sizeBytes, data.count)

        let url = try await api.attachmentURL(tripID: tripID, attachmentID: file.id)
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(try Data(contentsOf: url), data)

        try await api.deleteAttachment(tripID: tripID, attachmentID: file.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let remaining = try await api.attachments(tripID: tripID)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testOversizedFilesAreRefused() async {
        do {
            _ = try await api.uploadAttachment(tripID: tripID, data: Data(count: LocalTripStore.uploadLimitBytes + 1), fileName: "big.mov", mimeType: "video/quicktime")
            XCTFail("Over-limit files must be refused")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "file_too_large")
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testUnsupportedRoutesExplainThemselves() async {
        do {
            _ = try await api.invites(tripID: tripID)
            XCTFail("Invites are not available offline")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "not_available_offline")
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}

final class GuestTripImporterTests: XCTestCase {
    func testCopiesPlacesOntoTheSameDayAndCostsToThePayer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Two independent local servers stand in for the device and the account.
        let localStore = LocalTripStore(directory: root.appendingPathComponent("a"))
        let local = LocalTripServer.api(LocalTripServer(store: localStore))
        let remote = LocalTripServer.api(LocalTripServer(store: LocalTripStore(directory: root.appendingPathComponent("b"))))
        let guestTrip = UUID(), accountTrip = UUID(), payer = UUID()

        for index in 0..<2 {
            _ = try await local.addDay(tripID: guestTrip, index: index, date: "2026-12-0\(index + 1)")
            _ = try await remote.addDay(tripID: accountTrip, index: index, date: "2026-12-0\(index + 1)")
        }
        let localDay2 = try await local.days(tripID: guestTrip)[1]
        let place = try await local.addPlace(tripID: guestTrip, body: ["name": .string("Ryoan-ji"), "day_id": .optional(localDay2.id)])
        _ = try await local.addExpense(tripID: guestTrip, body: [
            "title": .string("Entry"), "amount": .number(5), "place_id": .optional(place.id), "splits": .array([])
        ])
        _ = try await local.addChecklistItem(tripID: guestTrip, title: "Passport", position: 0)

        _ = try await local.uploadAttachment(tripID: guestTrip, data: Data("pdf".utf8), fileName: "pass.pdf", mimeType: "application/pdf")

        let summary = try await GuestTripImporter.copy(
            localTripID: guestTrip, into: accountTrip, from: local, to: remote, payer: payer, localStore: localStore
        )
        XCTAssertEqual(summary, .init(places: 1, reservations: 0, expenses: 1, checklist: 1, files: 1))
        let copiedFiles = try await remote.attachments(tripID: accountTrip)
        XCTAssertEqual(copiedFiles.map(\.name), ["pass.pdf"])

        let remoteDay2 = try await remote.days(tripID: accountTrip)[1]
        let copied = try await remote.places(tripID: accountTrip)
        XCTAssertEqual(copied.first?.dayId, remoteDay2.id)
        let expense = try await remote.expenses(tripID: accountTrip).first
        XCTAssertEqual(expense?.paidBy, payer)
        XCTAssertEqual(expense?.placeId, copied.first?.id)
    }
}
