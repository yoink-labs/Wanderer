import XCTest
@testable import Wanderer

@MainActor
final class PlannerUndoTests: XCTestCase {
    private var directory: URL!
    private var api: WandererAPI!
    private var store: TripDetailStore!
    private let tripID = UUID()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        api = LocalTripServer.api(LocalTripServer(store: LocalTripStore(directory: directory)))
        for index in 0..<2 {
            _ = try await api.addDay(tripID: tripID, index: index, date: "2026-12-0\(index + 1)")
        }
        let day = try await api.days(tripID: tripID)[0]
        for (index, name) in ["Fushimi Inari", "Tofuku-ji", "Gion"].enumerated() {
            _ = try await api.addPlace(tripID: tripID, body: [
                "name": .string(name), "day_id": .optional(day.id), "position": .integer(index),
                "notes": .string("note \(index)"), "lat": .number(35 + Double(index) / 100), "lng": .number(135.7)
            ])
        }
        let trip = Trip(id: tripID, title: "T", destination: "Kyoto", dateRange: "", days: 2, places: 3,
                        members: [], palette: .kyoto, symbol: "leaf.fill")
        store = TripDetailStore(trip: trip, api: api)
        await store.load()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var dayOneNames: [String] { store.places(for: store.days[0].id).map(\.name) }

    func testUndoRestoresARemovedStopInPlaceWithItsDetails() async {
        let middle = store.places(for: store.days[0].id)[1]
        await store.deletePlace(middle)
        XCTAssertEqual(dayOneNames, ["Fushimi Inari", "Gion"])
        XCTAssertEqual(store.lastChange?.label, "Removed Tofuku-ji")

        await store.undo()
        XCTAssertEqual(dayOneNames, ["Fushimi Inari", "Tofuku-ji", "Gion"])
        XCTAssertEqual(store.places.first { $0.name == "Tofuku-ji" }?.notes, "note 1")

        await store.redo()
        XCTAssertEqual(dayOneNames, ["Fushimi Inari", "Gion"])
    }

    func testReorderUndoesAndRedoes() async {
        await store.movePlaces(in: store.days[0].id, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(dayOneNames, ["Tofuku-ji", "Gion", "Fushimi Inari"])
        await store.undo()
        XCTAssertEqual(dayOneNames, ["Fushimi Inari", "Tofuku-ji", "Gion"])
        await store.redo()
        XCTAssertEqual(dayOneNames, ["Tofuku-ji", "Gion", "Fushimi Inari"])
    }

    func testMovingToAnotherDayUndoes() async {
        let gion = store.places(for: store.days[0].id)[2]
        await store.assign(gion, to: store.days[1].id)
        XCTAssertEqual(store.places(for: store.days[1].id).map(\.name), ["Gion"])
        XCTAssertEqual(store.lastChange?.label, "Moved Gion to Day 2")
        await store.undo()
        XCTAssertEqual(dayOneNames, ["Fushimi Inari", "Tofuku-ji", "Gion"])
        XCTAssertTrue(store.places(for: store.days[1].id).isEmpty)
    }

    func testVisitedToggleUndoes() async {
        let first = store.places(for: store.days[0].id)[0]
        await store.setVisited(first, visited: true)
        XCTAssertTrue(store.places.first { $0.id == first.id }?.isVisited == true)
        await store.undo()
        XCTAssertTrue(store.places.first { $0.id == first.id }?.isVisited == false)
    }

    func testOlderStepsStillFindARecreatedStop() async {
        let tofuku = store.places(for: store.days[0].id)[1]
        await store.setVisited(tofuku, visited: true)
        await store.deletePlace(store.places.first { $0.id == tofuku.id }!)
        await store.undo()   // restores Tofuku-ji with a new id, still visited
        XCTAssertTrue(store.places.first { $0.name == "Tofuku-ji" }?.isVisited == true)
        await store.undo()   // un-visits the restored stop through the id alias
        XCTAssertTrue(store.places.first { $0.name == "Tofuku-ji" }?.isVisited == false)
    }

    func testNewEditClearsRedoAndStackIsBounded() async {
        let first = store.places(for: store.days[0].id)[0]
        await store.setVisited(first, visited: true)
        await store.undo()
        XCTAssertTrue(store.canRedo)
        await store.setVisited(first, visited: true)
        XCTAssertFalse(store.canRedo)
        for _ in 0..<(TripDetailStore.undoLimit + 5) {
            await store.movePlaces(in: store.days[0].id, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        }
        XCTAssertEqual(store.undoStack.count, TripDetailStore.undoLimit)
    }
}
