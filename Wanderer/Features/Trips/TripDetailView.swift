import SwiftUI

struct TripDetailView: View {
    let trip: Trip

    @State private var selectedDay = 0

    private let samplePlaces: [[(String, String, String)]] = [
        [
            ("Fushimi Inari Shrine", "Shrine · 8:00 AM", "building.columns.fill"),
            ("Nishiki Market", "Food · 12:30 PM", "fork.knife"),
            ("Gion district walk", "Sightseeing · 4:00 PM", "figure.walk")
        ],
        [
            ("Arashiyama Bamboo Grove", "Nature · 9:00 AM", "tree"),
            ("Sagano Romantic Train", "Transport · 1:00 PM", "tram"),
            ("Tenryū-ji Temple", "Temple · 3:30 PM", "building.columns")
        ],
        [
            ("Kinkaku-ji", "Temple · 9:30 AM", "sun.max"),
            ("Philosopher's Path", "Walk · 1:00 PM", "figure.walk"),
            ("Nanzen-ji", "Temple · 3:00 PM", "building.columns")
        ]
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                cover
                dayPicker

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Day \(selectedDay + 1)",
                        subtitle: selectedDay == 0 ? "Arrival & first look" : "Slow morning, big walk"
                    )

                    ForEach(Array(samplePlaces[selectedDay % samplePlaces.count].enumerated()), id: \.offset) { item in
                        placeRow(index: item.offset, place: item.element)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Reservations", subtitle: "2 bookings")
                    reservationRow(title: "Hotel Gran Ms Kyoto", detail: "Nov 12 – 17 · Confirmation HX-8821", icon: "bed.double.fill")
                    reservationRow(title: "KIX → ITM", detail: "Nov 12 · 10:35 AM · JL 128", icon: "airplane")
                }
            }
            .padding(.horizontal, WandererTheme.screenPadding)
            .padding(.bottom, 30)
        }
        .background(WandererTheme.sand.ignoresSafeArea())
        .contentMargins(.bottom, 24, for: .scrollContent)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: trip.palette.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: trip.symbol)
                .font(.system(size: 110, weight: .bold))
                .foregroundStyle(.white.opacity(0.12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(18)

            VStack(alignment: .leading, spacing: 6) {
                Text(trip.destination)
                    .font(.ligga(.subheadline, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text(trip.title)
                    .wandererHeading(.hero)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(trip.dateRange)
                    Text("·")
                    Text("\(trip.days) days")
                    Text("·")
                    Text("\(trip.places) places")
                }
                .font(.ligga(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(20)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 8)
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(0..<trip.days, id: \.self) { index in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedDay = index
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Day")
                                .font(.ligga(.caption2, weight: .medium))
                            Text("\(index + 1)")
                                .font(.ligga(.headline, weight: .bold))
                        }
                        .frame(width: 62, height: 58)
                        .foregroundStyle(index == selectedDay ? .white : WandererTheme.ink)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(index == selectedDay ? WandererTheme.ink : .white)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func placeRow(index: Int, place: (String, String, String)) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WandererTheme.coralSoft)
                Image(systemName: place.2)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.0)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                Text(place.1)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
            }

            Spacer()

            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 24, height: 24)
                .background(WandererTheme.sandDeep.opacity(0.7), in: Circle())
        }
        .padding(12)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reservationRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WandererTheme.sandDeep.opacity(0.6))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                Text(detail)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
            }

            Spacer()
        }
        .padding(12)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: Trip.samples[0])
    }
}
