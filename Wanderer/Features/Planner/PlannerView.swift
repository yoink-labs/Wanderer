import MapKit
import SwiftUI

struct PlannerView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store: TripDetailStore

    @State private var selection: PlannerSelection = .unscheduled
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// The stop highlighted on both the map and the itinerary list.
    @State private var focusedPlaceID: UUID?
    /// Set when the map picks a stop, so the list scrolls its row into view.
    @State private var listScrollTarget: UUID?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var viewport = PlannerViewport()
    @State private var activeSheet: PlannerSheet?
    @State private var editMode: EditMode = .inactive
    @State private var weather: WeatherService.Snapshot?
    @State private var panelFraction: CGFloat = 0.55
    @State private var panelDragStart: CGFloat?
    @State private var placePendingDelete: PlaceRecord?
    @State private var addedCount = 0
    @State private var removedCount = 0
    @State private var detentIndex = 1

    private static let detents: [CGFloat] = [0.16, 0.52, 0.9]
    private static let detentNames = ["Collapsed", "Half", "Expanded"]

    init(trip: Trip) {
        self.trip = trip
        _store = StateObject(wrappedValue: TripDetailStore(trip: trip))
    }

    // MARK: - Selection & sheets

    private enum PlannerSelection: Hashable {
        case day(UUID)
        case unscheduled
    }

    private enum PlannerSheet: Identifiable {
        case addPlace
        case reservations
        case share
        case settings
        case notes
        case attachments
        case nearby
        case dayNote(TripDayRecord)
        case place(PlaceRecord)

        var id: String {
            switch self {
            case .addPlace:
                return "add-place"
            case .reservations:
                return "reservations"
            case .share:
                return "share"
            case .settings:
                return "settings"
            case .notes:
                return "notes"
            case .attachments:
                return "attachments"
            case .nearby:
                return "nearby"
            case .dayNote(let day):
                return "day-note-\(day.id.uuidString)"
            case .place(let place):
                return "place-\(place.id.uuidString)"
            }
        }
    }

    // MARK: - Derived state

    /// Places in itinerary order: assigned days first (by day index), then the
    /// unscheduled bucket, each sorted by the order the store holds them in.
    private var orderedPlaces: [PlaceRecord] {
        let dayOrder = Dictionary(
            uniqueKeysWithValues: store.days.enumerated().map { ($0.element.id, $0.offset) }
        )

        return store.places.sorted { lhs, rhs in
            let leftDay = lhs.dayId.flatMap { dayOrder[$0] } ?? Int.max
            let rightDay = rhs.dayId.flatMap { dayOrder[$0] } ?? Int.max
            if leftDay != rightDay { return leftDay < rightDay }
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var coordinateSignature: String {
        orderedPlaces
            .compactMap { place -> String? in
                guard let coordinate = place.coordinate else { return nil }
                return "\(place.id.uuidString):\(coordinate.latitude),\(coordinate.longitude)"
            }
            .joined(separator: "|")
    }

    private var selectedPlaces: [PlaceRecord] {
        switch selection {
        case .day(let dayID):
            return store.places(for: dayID)
        case .unscheduled:
            return store.unassignedPlaces
        }
    }

    private var otherPlaces: [PlaceRecord] {
        let selectedIDs = Set(selectedPlaces.map(\.id))
        return store.places.filter { !selectedIDs.contains($0.id) }
    }

    private var currentDayID: UUID? {
        if case .day(let dayID) = selection { return dayID }
        return nil
    }

    private var currentDay: TripDayRecord? {
        guard let currentDayID else { return nil }
        return store.days.first { $0.id == currentDayID }
    }

    private var showsUnscheduledChip: Bool {
        !store.unassignedPlaces.isEmpty || selection == .unscheduled
    }

    /// Straight-line legs between consecutive pinned stops of the selected day,
    /// keyed by the stop they arrive at. Matches the route drawn on the map.
    private var travelLegs: [UUID: PlannerTravelLeg] {
        guard case .day = selection else { return [:] }
        var legs: [UUID: PlannerTravelLeg] = [:]
        var previous: CLLocationCoordinate2D?
        for place in selectedPlaces {
            guard let coordinate = place.mapCoordinate else { continue }
            if let previous {
                legs[place.id] = PlannerTravelLeg(from: previous, to: coordinate)
            }
            previous = coordinate
        }
        return legs
    }

    private var currentDetentIndex: Int {
        Self.detents.enumerated()
            .min(by: { abs($0.element - panelFraction) < abs($1.element - panelFraction) })?
            .offset ?? 1
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                PlannerMapView(
                    selectedPlaces: selectedPlaces,
                    otherPlaces: otherPlaces,
                    cameraPosition: $cameraPosition,
                    focusedPlaceID: focusedPlaceID,
                    onSelectPlace: { place in selectFromMap(place) },
                    onRegionChange: { region in visibleRegion = region }
                )
                .ignoresSafeArea()

                panel(height: proxy.size.height)
                    .frame(height: panelHeight(for: proxy.size.height))
                    .background(panelBackground)
            }
            .onAppear { updateViewport(proxy) }
            .onChange(of: proxy.size) { _, _ in updateViewport(proxy) }
        }
        .background(WandererTheme.sand)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                plannerMenu
                if selectedPlaces.contains(where: { $0.coordinate != nil }) {
                    fitDayButton
                }
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .task { await bootstrap() }
        .onChange(of: coordinateSignature) { _, _ in
            framePlaces()
        }
        .onChange(of: selection) { _, _ in
            editMode = .inactive
            focusedPlaceID = nil
            framePlaces()
        }
        .onChange(of: store.places) { _, places in
            if let focusedPlaceID, !places.contains(where: { $0.id == focusedPlaceID }) {
                self.focusedPlaceID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in
            dismiss()
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .confirmationDialog(
            "Remove this place?",
            isPresented: Binding(
                get: { placePendingDelete != nil },
                set: { if !$0 { placePendingDelete = nil } }
            ),
            presenting: placePendingDelete
        ) { place in
            Button("Remove \(place.name)", role: .destructive) {
                Task { await store.deletePlace(place) }
                placePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { placePendingDelete = nil }
        } message: { _ in
            Text("This removes the stop from the itinerary.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.selection, trigger: focusedPlaceID)
        .sensoryFeedback(.success, trigger: addedCount)
        .sensoryFeedback(.warning, trigger: removedCount)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: detentIndex)
        .onChange(of: store.places.count) { oldValue, newValue in
            if newValue > oldValue {
                addedCount += 1
            } else if newValue < oldValue {
                removedCount += 1
            }
        }
    }

    // MARK: - Panel

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                panelGrabber

                tripHeader
                    .padding(.horizontal, WandererTheme.screenPadding)
                    .padding(.top, 8)
            }
            .contentShape(Rectangle())
            .gesture(panelDragGesture(height: height))

            dayChips
                .padding(.top, 10)

            sectionHeader
                .padding(.horizontal, WandererTheme.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 3)

            if let note = currentDay?.notes, !note.isEmpty {
                dayNoteBanner(note)
                    .padding(.horizontal, WandererTheme.screenPadding)
                    .padding(.vertical, -4)
            }

            placesArea
                .frame(maxHeight: .infinity)
        }
    }

    /// Drag handle. VoiceOver users resize the panel with swipe up/down
    /// (adjustable), everyone else can drag or tap it.
    private var panelGrabber: some View {
        Capsule()
            .fill(WandererTheme.line)
            .frame(width: 36, height: 4)
            .padding(.top, 7)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                stepDetent(by: currentDetentIndex == Self.detents.count - 1 ? -1 : 1)
            }
            .accessibilityElement()
            .accessibilityLabel("Itinerary panel")
            .accessibilityValue(Self.detentNames[currentDetentIndex])
            .accessibilityHint("Swipe up or down to resize")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    stepDetent(by: 1)
                case .decrement:
                    stepDetent(by: -1)
                @unknown default:
                    break
                }
            }
            .accessibilityIdentifier("planner-panel-handle")
    }

    private var panelBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
            .fill(WandererTheme.card)
            .shadow(color: WandererTheme.charcoal.opacity(0.15), radius: 16, x: 0, y: -5)
            .ignoresSafeArea(edges: .bottom)
    }

    private func panelHeight(for height: CGFloat) -> CGFloat {
        min(max(height * panelFraction, 150), height - 70)
    }

    private func panelDragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if panelDragStart == nil {
                    panelDragStart = panelFraction
                }
                let delta = -value.translation.height / max(1, height)
                panelFraction = min(max((panelDragStart ?? panelFraction) + delta, 0.16), 0.92)
            }
            .onEnded { _ in
                panelDragStart = nil
                setDetent(currentDetentIndex)
            }
    }

    private func stepDetent(by delta: Int) {
        setDetent(min(max(currentDetentIndex + delta, 0), Self.detents.count - 1))
    }

    private func setDetent(_ index: Int) {
        detentIndex = index
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) {
            panelFraction = Self.detents[index]
        }
        refocusCamera()
    }

    private var tripHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title)
                    .font(.ligga(.title3, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(trip.dateRange)
                    Text("·")
                    Text("\(trip.days) days")
                    Text("·")
                    Text("\(store.places.count) places")
                }
                .font(.ligga(.footnote, weight: .medium))
                .foregroundStyle(WandererTheme.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let weather {
                weatherCapsule(weather)
            }
        }
    }

    private func weatherCapsule(_ snapshot: WeatherService.Snapshot) -> some View {
        let summary = WeatherService.summary(for: snapshot.code)
        return HStack(spacing: 5) {
            Image(systemName: WeatherService.symbol(for: snapshot.code))
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.coral)
            Text("\(Int(snapshot.temperature.rounded()))°")
                .font(.ligga(.subheadline, weight: .bold))
                .foregroundStyle(WandererTheme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(WandererTheme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Weather: \(Int(snapshot.temperature.rounded())) degrees, \(summary)"
        )
    }

    private var dayChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.days) { day in
                        dayChip(for: day)
                            .id(PlannerSelection.day(day.id))
                    }

                    if showsUnscheduledChip {
                        unscheduledChip
                            .id(PlannerSelection.unscheduled)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: store.days.count) { _, _ in
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }

    private func dayChip(for day: TripDayRecord) -> some View {
        let isSelected = selection == .day(day.id)
        let labels = chipLabels(for: day)

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = .day(day.id)
            }
        } label: {
            VStack(spacing: 0) {
                Text(labels.0)
                    .font(.ligga(.caption2, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : WandererTheme.muted)
                Text(labels.1)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white : WandererTheme.ink)
            }
            .frame(minWidth: 58, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? WandererTheme.charcoal : WandererTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? .clear : WandererTheme.line, lineWidth: 1)
            )
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("planner-day-\(day.dayIndex)")
        .accessibilityLabel("Day \(day.dayIndex + 1), \(labels.0) \(labels.1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var unscheduledChip: some View {
        let isSelected = selection == .unscheduled
        let count = store.unassignedPlaces.count

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = .unscheduled
            }
        } label: {
            VStack(spacing: 0) {
                Text("NO DAY")
                    .font(.ligga(.caption2, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(isSelected ? .white.opacity(0.75) : WandererTheme.muted)
                Text("\(count)")
                    .font(.ligga(.subheadline, weight: .bold))
                    .foregroundStyle(isSelected ? .white : WandererTheme.ink)
            }
            .frame(minWidth: 62, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? WandererTheme.charcoal : WandererTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? .clear : WandererTheme.line, lineWidth: 1)
            )
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("planner-day-unassigned")
        .accessibilityLabel("Unassigned places, \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chipLabels(for day: TripDayRecord) -> (String, String) {
        guard day.date != nil, TripDayRecord.date(from: day.date) != nil else {
            return ("DAY", "\(day.dayIndex + 1)")
        }
        return (day.weekdayLabel.uppercased(), day.shortDateLabel)
    }

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(sectionTitle)
                    .font(.ligga(.title3, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                Text(sectionSubtitle)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Menu {
                if selectedPlaces.count > 1 {
                    Button {
                        toggleEditMode()
                    } label: {
                        Label(
                            editMode.isEditing ? "Done arranging" : "Arrange places",
                            systemImage: "arrow.up.arrow.down"
                        )
                    }
                }

                if let currentDay {
                    Button {
                        activeSheet = .dayNote(currentDay)
                    } label: {
                        Label("Day note", systemImage: "note.text")
                    }
                }
            } label: {
                Text("Day options")
                    .font(.ligga(.caption, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Day options")

            Button {
                activeSheet = .addPlace
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.accentText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("planner-add-place")
        }
    }

    private var sectionTitle: String {
        switch selection {
        case .day:
            guard let currentDay else { return "Places" }
            return "Day \(currentDay.dayIndex + 1)"
        case .unscheduled:
            return "Unscheduled"
        }
    }

    private var sectionSubtitle: String {
        let count = selectedPlaces.count
        let stops = "\(count) \(count == 1 ? "stop" : "stops")"

        switch selection {
        case .day:
            guard let currentDay, currentDay.date != nil else { return stops }
            // Counts and distance live in the itinerary summary line; when the
            // list is empty there is no summary, so keep them here.
            return selectedPlaces.isEmpty ? "\(currentDay.fullDateLabel) · \(stops)" : currentDay.fullDateLabel
        case .unscheduled:
            return count == 0 ? "Every place has a day" : "\(stops) without a day"
        }
    }

    // MARK: - Bookings

    private var selectedReservations: [ReservationRecord] {
        guard let currentDay,
              let date = TripDayRecord.date(from: currentDay.date) else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        return store.reservations.filter { reservation in
            guard let start = reservation.parsedStart else { return false }
            let end = reservation.parsedEnd ?? start
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            return dayStart >= startDay && dayStart <= endDay
        }
    }

    private func bookingStage(_ reservation: ReservationRecord) -> String {
        guard let currentDay,
              let date = TripDayRecord.date(from: currentDay.date),
              let start = reservation.parsedStart else {
            return reservation.type.title.uppercased()
        }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: reservation.parsedEnd ?? start)

        if startDay == day {
            switch reservation.type {
            case .flight: return "DEPARTS"
            case .lodging: return "CHECK IN"
            default: return "STARTS"
            }
        }
        if endDay == day {
            switch reservation.type {
            case .flight: return "ARRIVES"
            case .lodging: return "CHECK OUT"
            default: return "ENDS"
            }
        }
        return "STAYING"
    }

    private func dayNoteBanner(_ note: String) -> some View {
        Button {
            if let currentDay {
                activeSheet = .dayNote(currentDay)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text")
                    .font(.ligga(.footnote, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
                Text(note)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.charcoal)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.ligga(.caption, weight: .bold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WandererTheme.coralSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // Visual chip stays one slim line; the tappable area is 44pt tall.
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day note: \(note)")
        .accessibilityHint("Edits the day note")
        .accessibilityIdentifier("planner-day-note")
    }

    @ViewBuilder
    private var placesArea: some View {
        if store.isLoading && store.places.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(WandererTheme.coral)
                Text("Loading your plans…")
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedPlaces.isEmpty && selectedReservations.isEmpty {
            emptyPlaces
        } else {
            placesList
        }
    }

    private var emptyPlaces: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(WandererTheme.coralSoft)
                Image(systemName: selection == .unscheduled ? "tray" : "map")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 50, height: 50)

            Text(selection == .unscheduled ? "Nothing left unscheduled" : "Nothing planned yet")
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)

            Text(
                selection == .unscheduled
                    ? "Places you add without a day will land here."
                    : "Add a place to start shaping this day."
            )
            .font(.ligga(.caption))
            .foregroundStyle(WandererTheme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            PrimaryButton(title: "Add a place", icon: "plus") {
                activeSheet = .addPlace
            }
            .padding(.horizontal, 48)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 10)
    }

    private var placesList: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(Array(selectedPlaces.enumerated()), id: \.element.id) { index, place in
                        placeRow(place, number: index + 1)
                    }
                    .onMove { fromOffsets, toOffset in
                        let dayID = currentDayID
                        Task {
                            await store.movePlaces(in: dayID, fromOffsets: fromOffsets, toOffset: toOffset)
                        }
                    }

                    addPlaceRow
                } header: {
                    if !selectedPlaces.isEmpty {
                        daySummaryHeader
                    }
                }

                if !selectedReservations.isEmpty {
                    Section {
                        ForEach(selectedReservations) { reservation in
                            Button {
                                activeSheet = .reservations
                            } label: {
                                bookingRow(reservation)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 2, leading: WandererTheme.screenPadding, bottom: 2, trailing: WandererTheme.screenPadding))
                            .listRowBackground(WandererTheme.card)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        listHeader("Bookings")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .environment(\.editMode, $editMode)
            .scrollIndicators(.hidden)
            .padding(.bottom, 4)
            .onChange(of: listScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                listScrollTarget = nil
            }
        }
    }

    private func placeRow(_ place: PlaceRecord, number: Int) -> some View {
        let isFocused = focusedPlaceID == place.id

        return Button {
            selectFromList(place)
        } label: {
            PlannerPlaceRow(
                place: place,
                number: number,
                timeZoneIdentifier: trip.timezone,
                isFocused: isFocused,
                leg: editMode.isEditing ? nil : travelLegs[place.id]
            )
        }
        .buttonStyle(.plain)
        .id(place.id)
        .listRowInsets(EdgeInsets(top: 2, leading: WandererTheme.screenPadding, bottom: 2, trailing: WandererTheme.screenPadding))
        .listRowBackground(isFocused ? WandererTheme.coralSoft.opacity(0.5) : WandererTheme.card)
        // On a day the travel connector separates stops; unscheduled keeps hairlines.
        .listRowSeparator(selection == .unscheduled ? .visible : .hidden)
        .accessibilityIdentifier("planner-place-\(place.id.uuidString)")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityHint(isFocused ? "Opens place details" : "Shows this stop on the map")
        .accessibilityAction(named: "Show details") {
            activeSheet = .place(place)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                placePendingDelete = place
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var addPlaceRow: some View {
        HStack(spacing: 8) {
            Button {
                activeSheet = .addPlace
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.ligga(.body, weight: .medium))
                    Text(selectedPlaces.isEmpty ? "Add a place to \(sectionTitle.lowercased())" : "Add another place")
                        .font(.ligga(.subheadline, weight: .medium))
                }
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 8)

            Button {
                activeSheet = .nearby
            } label: {
                Label("Nearby", systemImage: "sparkle.magnifyingglass")
                    .font(.ligga(.subheadline, weight: .medium))
                    .foregroundStyle(WandererTheme.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Nearby ideas")
            .accessibilityIdentifier("planner-nearby")
        }
        .listRowInsets(EdgeInsets(top: 0, leading: WandererTheme.screenPadding, bottom: 6, trailing: WandererTheme.screenPadding))
        .listRowBackground(WandererTheme.card)
        .listRowSeparator(.hidden)
        .moveDisabled(true)
    }

    /// "3 STOPS · 1 BOOKING · 4.2 KM" — replaces the old ITINERARY overline.
    private var daySummaryHeader: some View {
        let stopCount = selectedPlaces.count
        let bookingCount = selectedReservations.count
        let totalMeters = travelLegs.values.reduce(0) { $0 + $1.meters }

        var parts = ["\(stopCount) \(stopCount == 1 ? "stop" : "stops")"]
        if bookingCount > 0 {
            parts.append("\(bookingCount) \(bookingCount == 1 ? "booking" : "bookings")")
        }
        if totalMeters > 0 {
            parts.append(PlannerDistanceFormat.string(totalMeters))
        }

        return listHeader(parts.joined(separator: " · "))
            .accessibilityLabel(
                parts.joined(separator: ", ") + (totalMeters > 0 ? " in a straight line" : "")
            )
            .accessibilityIdentifier("planner-day-summary")
    }

    private func listHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.ligga(.caption, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(WandererTheme.muted)
            .lineLimit(1)
            .textCase(nil)
            // Plain-list headers sit 4pt left of the panel gutter.
            .padding(.leading, 4)
            .padding(.top, 2)
            .padding(.bottom, 2)
    }

    private func bookingRow(_ reservation: ReservationRecord) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(WandererTheme.desert)
                .frame(width: 3, height: 34)

            Image(systemName: reservation.type.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(bookingStage(reservation))
                    .font(.ligga(.caption2, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(WandererTheme.muted)
                Text(reservation.title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let time = reservation.timeLabel(in: trip.timezone) {
                Text(time)
                    .font(.ligga(.footnote, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WandererTheme.ink)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Toolbar & sheets

    private var plannerMenu: some View {
        Menu {
            Button {
                activeSheet = .reservations
            } label: {
                Label("Reservations & expenses", systemImage: "ticket")
            }

            Button {
                Task { await store.optimizeRoute(for: currentDayID) }
            } label: {
                Label("Optimize route", systemImage: "wand.and.stars")
            }
            .disabled(selectedPlaces.count < 2)

            Button {
                activeSheet = .nearby
            } label: {
                Label("Nearby ideas", systemImage: "mappin.and.ellipse")
            }

            Button {
                activeSheet = .share
            } label: {
                Label("Share trip", systemImage: "square.and.arrow.up")
            }

            Button {
                activeSheet = .notes
            } label: {
                Label("Trip notes", systemImage: "note.text")
            }

            Button {
                activeSheet = .attachments
            } label: {
                Label("Attachments", systemImage: "paperclip")
            }

            Divider()

            Button {
                activeSheet = .settings
            } label: {
                Label("Trip settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WandererTheme.charcoal)
                .frame(width: 44, height: 44)
                .background(WandererTheme.card, in: Circle())
                .shadow(color: WandererTheme.charcoal.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .accessibilityLabel("Trip tools")
        .accessibilityIdentifier("planner-tools")
    }

    private var fitDayButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                focusedPlaceID = nil
            }
            framePlaces()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WandererTheme.charcoal)
                .frame(width: 44, height: 44)
                .background(WandererTheme.card, in: Circle())
                .shadow(color: WandererTheme.charcoal.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection == .unscheduled ? "Fit unscheduled places on map" : "Fit day on map")
        .accessibilityIdentifier("planner-fit-day")
    }

    @ViewBuilder
    private func sheetContent(for sheet: PlannerSheet) -> some View {
        switch sheet {
        case .addPlace:
            PlaceSearchView(trip: trip, store: store, dayID: currentDayID)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .reservations:
            TripToolsView(trip: trip, store: store, initialTab: .reservations)
        case .share:
            TripToolsView(trip: trip, store: store, initialTab: .share)
        case .settings:
            TripSettingsView(trip: trip)
        case .notes:
            TripNotesView(trip: trip)
        case .attachments:
            TripAttachmentsView(trip: trip)
        case .nearby:
            NearbyIdeasView(trip: trip, store: store, dayID: currentDayID)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .dayNote(let day):
            DayNoteView(note: day.notes ?? "", day: day, store: store)
        case .place(let place):
            PlaceDetailSheet(place: place, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Actions

    private func toggleEditMode() {
        withAnimation(.easeOut(duration: 0.2)) {
            editMode = editMode.isEditing ? .inactive : .active
        }
    }

    private func bootstrap() async {
        await store.load()

        if case .unscheduled = selection, store.unassignedPlaces.isEmpty {
            let firstDayWithPlaces = store.days.first { !store.places(for: $0.id).isEmpty }
            if let day = firstDayWithPlaces ?? store.days.first {
                selection = .day(day.id)
            }
        }

        framePlaces()
        await frameDestinationIfNeeded()
        await loadWeather()
    }

    private func updateViewport(_ proxy: GeometryProxy) {
        viewport = PlannerViewport(
            size: proxy.size,
            safeTop: proxy.safeAreaInsets.top,
            safeBottom: proxy.safeAreaInsets.bottom
        )
    }

    /// The map is full-bleed; this is its size in points.
    private var mapSize: CGSize {
        viewport.mapSize
    }

    /// The strip of map that isn't under the nav bar or the panel.
    private var mapInsets: EdgeInsets {
        let panelOnScreen = panelHeight(for: viewport.contentHeight) + viewport.safeBottom
        return EdgeInsets(
            top: viewport.safeTop + 16,
            leading: 40,
            bottom: panelOnScreen + 28,
            trailing: 40
        )
    }

    private func framePlaces() {
        let coordinates = selectedPlaces.compactMap(\.mapCoordinate)
        guard let region = PlannerGeometry.fittingRegion(
            for: coordinates,
            in: mapSize,
            insets: mapInsets
        ) else {
            return
        }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            cameraPosition = .region(region)
        }
    }

    /// After the panel moves, keep the focused stop (or the whole day) in view.
    private func refocusCamera() {
        if let focusedPlaceID,
           let place = selectedPlaces.first(where: { $0.id == focusedPlaceID }),
           place.mapCoordinate != nil {
            center(on: place)
        } else {
            framePlaces()
        }
    }

    /// Pan so `place` sits in the middle of the visible strip, keeping the
    /// current zoom unless the map is zoomed far out past the day.
    private func center(on place: PlaceRecord) {
        guard let coordinate = place.mapCoordinate else { return }
        let size = mapSize
        let dayCoordinates = selectedPlaces.compactMap(\.mapCoordinate)
        let dayFit = PlannerGeometry.fittingRegion(for: dayCoordinates, in: size, insets: mapInsets)
            .map { PlannerGeometry.metersPerPoint(for: $0, height: size.height) } ?? 0
        var metersPerPoint = visibleRegion
            .map { PlannerGeometry.metersPerPoint(for: $0, height: size.height) } ?? 0

        if metersPerPoint <= 0 || (dayFit > 0 && metersPerPoint > dayFit * 1.5) {
            metersPerPoint = dayFit
        }
        guard metersPerPoint > 0 else { return }

        let region = PlannerGeometry.region(
            placing: coordinate,
            metersPerPoint: metersPerPoint,
            in: size,
            insets: mapInsets
        )
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            cameraPosition = .region(region)
        }
    }

    /// Row tap: first tap highlights the stop and brings its pin into view,
    /// a second tap on the highlighted row opens its details.
    private func selectFromList(_ place: PlaceRecord) {
        guard focusedPlaceID != place.id else {
            activeSheet = .place(place)
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            focusedPlaceID = place.id
        }
        center(on: place)
    }

    /// Pin tap: highlight the stop and scroll its row into view; tapping the
    /// highlighted pin again opens its details.
    private func selectFromMap(_ place: PlaceRecord) {
        guard focusedPlaceID != place.id else {
            activeSheet = .place(place)
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            focusedPlaceID = place.id
        }
        if currentDetentIndex == 0 {
            detentIndex = 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) {
                panelFraction = Self.detents[1]
            }
        }
        listScrollTarget = place.id
    }

    /// When a trip has no pinned places yet, still start the map on the destination.
    private func frameDestinationIfNeeded() async {
        guard store.places.contains(where: { $0.coordinate != nil }) == false else { return }
        guard let results = try? await MapSearchService.search(trip.destination, near: nil),
              let first = results.first else {
            return
        }

        let region = MKCoordinateRegion(
            center: first.coordinate,
            latitudinalMeters: 14_000,
            longitudinalMeters: 14_000
        )
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            cameraPosition = .region(region)
        }
    }

    private func loadWeather() async {
        guard let coordinate = selectedPlaces.compactMap(\.coordinate).first ?? store.places.compactMap(\.coordinate).first else { return }
        guard let snapshot = try? await WeatherService.current(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) else {
            return
        }

        withAnimation(.easeOut(duration: 0.3)) {
            weather = snapshot
        }
    }
}

// MARK: - Layout

private struct PlannerViewport: Equatable {
    /// The planner's content size (inside the safe area).
    var size: CGSize = .zero
    var safeTop: CGFloat = 0
    var safeBottom: CGFloat = 0

    /// Before the first layout pass, assume an iPhone 16-sized screen.
    var contentHeight: CGFloat {
        size.height > 0 ? size.height : 700
    }

    var mapSize: CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 393, height: 852)
        }
        return CGSize(width: size.width, height: size.height + safeTop + safeBottom)
    }
}

// MARK: - Place row

private struct PlannerPlaceRow: View {
    let place: PlaceRecord
    let number: Int
    let timeZoneIdentifier: String
    var isFocused = false
    /// Travel from the previous pinned stop, if any.
    var leg: PlannerTravelLeg?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let leg {
                PlannerLegConnector(leg: leg)
            }

            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(.caption, design: .default).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(isFocused ? .white : WandererTheme.charcoal)
                    .frame(width: 24, height: 24)
                    .background(
                        isFocused ? WandererTheme.charcoal : WandererTheme.desert.opacity(0.65),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.ligga(.headline))
                        .foregroundStyle(WandererTheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(place.category.title)
                        if let address = place.address, !address.isEmpty {
                            Text("·")
                            Text(address).lineLimit(1)
                        }
                    }
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)

                    if let notes = place.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.ligga(.footnote))
                            .foregroundStyle(WandererTheme.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if let time = place.timeLabel(in: timeZoneIdentifier) {
                    Text(time)
                        .font(.ligga(.caption2, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WandererTheme.coralDeep)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(WandererTheme.coralSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if let photoUrl = place.photoUrl,
                   let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            WandererTheme.dust.opacity(0.5)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                }

                if isFocused {
                    Image(systemName: "chevron.right")
                        .font(.ligga(.footnote, weight: .semibold))
                        .foregroundStyle(WandererTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
    }
}

/// "🚶 12 min walk · 0.9 km" between two stops, on a dotted rail that lines up
/// with the number badges.
private struct PlannerLegConnector: View {
    let leg: PlannerTravelLeg

    var body: some View {
        HStack(spacing: 10) {
            Path { path in
                path.move(to: CGPoint(x: 1, y: 0))
                path.addLine(to: CGPoint(x: 1, y: 18))
            }
            .stroke(
                WandererTheme.dust,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4])
            )
            .frame(width: 2, height: 18)
            .frame(width: 24)

            HStack(spacing: 5) {
                Image(systemName: leg.mode.symbol)
                    .font(.ligga(.caption, weight: .semibold))
                Text(leg.summary)
                    .font(.ligga(.footnote))
                    .lineLimit(1)
            }
            .foregroundStyle(WandererTheme.muted)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(leg.accessibilitySummary)
    }
}

#Preview {
    NavigationStack {
        PlannerView(trip: Trip.samples[0])
    }
}
