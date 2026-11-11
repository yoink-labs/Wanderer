import Foundation

#if DEBUG
/// Debug-only: fills the Kyoto sample guest trip with real places, bookings,
/// costs and a checklist through the local API, so screenshots show a lived-in
/// trip. Runs only with `-uiDemo YES` and only once per trip.
enum DemoTripSeed {
    static func runIfRequested() async {
        guard DebugLaunch.wantsDemo, LocalTrips.isActive,
              let trip = Trip.samples.first else { return }
        let api = LocalTripServer.api()
        guard let existing = try? await api.places(tripID: trip.id), existing.isEmpty,
              let days = try? await api.days(tripID: trip.id), days.count >= 3 else { return }

        let stops: [(Int, String, String, Double, Double, PlaceCategory, String?)] = [
            (0, "Fushimi Inari Taisha", "68 Fukakusa Yabunouchicho", 34.9671, 135.7727, .sight, "Go before 8 to beat the crowds"),
            (0, "Vermillion Café", "Fukakusa Kaidoguchicho", 34.9665, 135.7703, .food, nil),
            (0, "Tofuku-ji", "15-778 Honmachi", 34.9761, 135.7738, .sight, nil),
            (0, "Gion Shirakawa", "Shirakawa-minami-dori", 35.0055, 135.7764, .activity, "Evening walk"),
            (1, "Nishiki Market", "Nishikikoji-dori", 35.0050, 135.7649, .food, "Cash for the stalls"),
            (1, "Kinkaku-ji", "1 Kinkakujicho", 35.0394, 135.7292, .sight, nil),
            (1, "Ryoan-ji", "13 Ryoanji Goryonoshitacho", 35.0345, 135.7182, .sight, nil),
            (2, "Arashiyama Bamboo Grove", "Sagaogurayama", 35.0170, 135.6713, .sight, nil),
            (2, "Okochi Sanso", "8 Sagaogurayama Tabuchiyamacho", 35.0178, 135.6699, .sight, nil),
            (-1, "Kiyomizu-dera", "1-294 Kiyomizu", 34.9949, 135.7850, .sight, nil),
            (-1, "Pontocho Alley", "Pontocho", 35.0047, 135.7707, .food, nil)
        ]
        var created: [PlaceRecord] = []
        for (index, stop) in stops.enumerated() {
            let dayID: UUID? = stop.0 >= 0 ? days[stop.0].id : nil
            if let place = try? await api.addPlace(tripID: trip.id, body: [
                "day_id": .optional(dayID),
                "name": .string(stop.1),
                "address": .string(stop.2),
                "lat": .number(stop.3),
                "lng": .number(stop.4),
                "category": .string(stop.5.rawValue),
                "notes": .optional(stop.6),
                "position": .integer(index)
            ]) {
                created.append(place)
            }
        }
        if let first = created.first {
            _ = try? await api.setPlaceVisited(tripID: trip.id, placeID: first.id, visitedAt: ISO8601DateFormatter().string(from: Date()))
        }

        let start = TripDayRecord.date(from: trip.startDate) ?? Date()
        func at(_ day: Int, _ hour: Int) -> String {
            let date = Calendar.current.date(byAdding: .hour, value: day * 24 + hour, to: start) ?? start
            return ISO8601DateFormatter().string(from: date)
        }
        _ = try? await api.addReservation(tripID: trip.id, body: [
            "type": .string("flight"), "title": .string("NRT → ITM"), "provider": .string("JAL 105"),
            "confirmation_code": .string("Q7ZK2M"), "start_at": .string(at(0, 1)), "end_at": .string(at(0, 2)),
            "start_location": .string("Tokyo Narita"), "end_location": .string("Osaka Itami"),
            "cost": .number(184), "currency": .string("USD")
        ])
        _ = try? await api.addReservation(tripID: trip.id, body: [
            "type": .string("lodging"), "title": .string("Machiya near Gion"), "provider": .string("Kyoto Machiya Stay"),
            "start_at": .string(at(0, 6)), "end_at": .string(at(4, 1)), "cost": .number(620), "currency": .string("USD")
        ])

        let me = LocalTripStore.localUserID
        // Day offsets from the trip start; negative means paid before the trip.
        let expenses: [(String, Double, String, Int)] = [
            ("Machiya near Gion", 620, "lodging", -30), ("Flights", 184, "transport", -45),
            ("Fushimi breakfast", 22, "food", 0), ("Tofuku-ji entry", 8, "activities", 0),
            ("Nishiki Market lunch", 38, "food", 1), ("Kinkaku-ji entry", 4, "activities", 1),
            ("Kaiseki dinner", 160, "food", 1), ("Kimono rental", 55, "shopping", 2),
            ("Arashiyama rickshaw", 90, "activities", 2)
        ]
        for expense in expenses {
            let day = Calendar.current.date(byAdding: .day, value: expense.3, to: start) ?? start
            _ = try? await api.addExpense(tripID: trip.id, body: [
                "title": .string(expense.0), "amount": .number(expense.1), "currency": .string("USD"),
                "category": .string(expense.2), "paid_by": .string(me), "split_with": .array([.string(me)]),
                "split_mode": .string("equal"), "spent_at": .string(Trip.isoDay(day)), "splits": .array([])
            ])
        }
        for (index, item) in ["Passport", "Suica card", "Rail pass voucher", "Comfortable shoes", "Pocket wifi"].enumerated() {
            if let row = try? await api.addChecklistItem(tripID: trip.id, title: item, position: index), index < 2 {
                _ = try? await api.updateChecklistItem(tripID: trip.id, itemID: row.id, isChecked: true)
            }
        }
        _ = try? await api.addList(tripID: trip.id, title: "Maybe", position: 0)
    }
}
#endif
