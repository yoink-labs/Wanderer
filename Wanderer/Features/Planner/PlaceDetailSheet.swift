import SwiftUI

/// Inspect and edit a saved place: photo, rating and price when known,
/// category, notes and quick links.
struct PlaceDetailSheet: View {
    let place: PlaceRecord
    @ObservedObject var store: TripDetailStore

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: PlaceCategory
    @State private var notes: String
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var showCostPrompt = false
    @State private var costAmount = ""

    init(place: PlaceRecord, store: TripDetailStore) {
        self.place = place
        self.store = store
        _name = State(initialValue: place.name)
        _category = State(initialValue: place.category)
        _notes = State(initialValue: place.notes ?? "")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if let photoURL {
                    photoHeader(photoURL)
                }
                header
                if hasFacts {
                    factsRow
                }
                statusCard
                categoryCard
                notesCard
                personalCard
                if websiteURL != nil || phoneURL != nil {
                    linksCard
                }
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(WandererTheme.sand.ignoresSafeArea())
        .alert("Add a cost", isPresented: $showCostPrompt) {
            TextField("Amount", text: $costAmount)
                .keyboardType(.decimalPad)
            Button("Add") { addCost() }
            Button("Cancel", role: .cancel) { costAmount = "" }
        } message: {
            Text("This adds an expense tagged to \(currentPlace.name).")
        }
        .confirmationDialog(
            "Remove this place?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove place", role: .destructive) {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                isPrivateStop
                    ? "“\(place.name)” is only in your itinerary. This removes it for you."
                    : "“\(place.name)” will be removed from this trip for everyone. This can't be undone."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(WandererTheme.coralSoft)
                Image(systemName: category.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Place name", text: $name, axis: .vertical)
                    .font(.ligga(.title3, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("place-name-field")

                if isPrivateStop || hasPersonalOverride {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(isPrivateStop ? "Only you" : "Your version")
                            .font(.ligga(.caption2, weight: .bold))
                    }
                    .foregroundStyle(WandererTheme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WandererTheme.coral, in: Capsule())
                    .accessibilityLabel(isPrivateStop ? "Private stop, only you can see it" : "Your private version")
                }

                if let address = place.address, !address.isEmpty {
                    Text(address)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(2)
                }

                if let time = place.timeLabel(in: store.trip.timezone) {
                    Text(time)
                        .font(.ligga(.caption, weight: .bold))
                        .foregroundStyle(WandererTheme.accentText)
                }
            }

            Spacer(minLength: 4)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.ligga(.footnote, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(WandererTheme.card, in: Circle())
                    .overlay(Circle().stroke(WandererTheme.line, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Photo & facts

    private func photoHeader(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                ZStack {
                    WandererTheme.dust.opacity(0.5)
                    Image(systemName: "photo")
                        .font(.ligga(.title2))
                        .foregroundStyle(WandererTheme.muted)
                }
            default:
                WandererTheme.dust.opacity(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Photo of \(place.name)")
        .accessibilityIdentifier("place-photo")
    }

    private var hasFacts: Bool {
        ratingValue != nil || priceLevelValue != nil
    }

    private var factsRow: some View {
        HStack(spacing: 8) {
            if let rating = ratingValue {
                factChip {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(WandererTheme.peach)
                        Text(rating, format: .number.precision(.fractionLength(1)))
                            .foregroundStyle(WandererTheme.ink)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: "Rated %.1f out of 5", rating))
            }

            if let level = priceLevelValue {
                factChip {
                    HStack(spacing: 0) {
                        Text(String(repeating: "$", count: level))
                            .foregroundStyle(WandererTheme.ink)
                        Text(String(repeating: "$", count: max(0, 4 - level)))
                            .foregroundStyle(WandererTheme.muted.opacity(0.55))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Price level \(level) of 4")
            }

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("place-facts")
    }

    private func factChip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.ligga(.subheadline, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(WandererTheme.card, in: Capsule())
            .overlay(Capsule().stroke(WandererTheme.line, lineWidth: 1))
    }

    /// Ratings are stored 0–5; anything else is treated as missing.
    private var ratingValue: Double? {
        guard let rating = place.rating, rating > 0, rating <= 5 else { return nil }
        return rating
    }

    /// Price levels are 1–4 dollar signs; 0 or missing shows nothing.
    private var priceLevelValue: Int? {
        guard let level = place.priceLevel, level > 0 else { return nil }
        return min(level, 4)
    }

    private var photoURL: URL? {
        guard let raw = place.photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased().hasPrefix("http") == true else {
            return nil
        }
        return url
    }

    // MARK: - Category

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category")
                .font(.ligga(.caption, weight: .bold))
                .foregroundStyle(WandererTheme.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlaceCategory.allCases) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                category = item
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.icon)
                                    .font(.ligga(.caption, weight: .semibold))
                                Text(item.title)
                                    .font(.ligga(.caption, weight: .semibold))
                            }
                            .foregroundStyle(category == item ? .white : WandererTheme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background(
                                category == item
                                    ? WandererTheme.ink
                                    : WandererTheme.sandDeep.opacity(0.55),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.ligga(.subheadline, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)

                Spacer()

                Text("Just for your trip")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
            }

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Opening hours, what to order, who recommended it…")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted.opacity(0.7))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes)
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 130)
                    .accessibilityIdentifier("place-notes-field")
            }
            .background(
                WandererTheme.sand,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .padding(16)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Status & cost

    /// The latest copy of the place: the sheet keeps its own snapshot, while the
    /// store refreshes after each write. Uses the member's view, so a private
    /// replacement shows its replaced values.
    private var currentPlace: PlaceRecord {
        store.visiblePlaces.first(where: { $0.id == place.id }) ?? place
    }

    private var isPrivateStop: Bool { store.isPrivate(place) }

    private var hasPersonalOverride: Bool {
        store.personalOverride(for: place.id) != nil
    }

    /// "Just for me": hide a shared stop or save a private version of it.
    /// Private stops are already only yours, so the card is not shown for them.
    @ViewBuilder
    private var personalCard: some View {
        if !isPrivateStop && !LocalTrips.isActive {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.ligga(.title3, weight: .semibold))
                        .foregroundStyle(WandererTheme.coralDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Just for me")
                            .font(.ligga(.subheadline, weight: .bold))
                            .foregroundStyle(WandererTheme.ink)
                        Text(
                            hasPersonalOverride
                                ? "You've changed this stop. Everyone else still sees the shared version."
                                : "Hide it or change its details without touching the group plan."
                        )
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if hasPersonalOverride {
                    Button {
                        Task {
                            await store.restoreForMe(place)
                            dismiss()
                        }
                    } label: {
                        Label("Restore the shared version", systemImage: "arrow.uturn.backward")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.coralDeep)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(WandererTheme.sandDeep.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place-restore-shared")
                } else {
                    Button {
                        Task {
                            await store.hideForMe(place)
                            dismiss()
                        }
                    } label: {
                        Label("Hide this stop for me", systemImage: "eye.slash")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.coralDeep)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(WandererTheme.sandDeep.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place-hide-for-me")
                }
            }
            .padding(16)
            .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var placeCost: Double {
        store.cost(for: currentPlace)
    }

    private var costCurrency: String {
        store.expenses.first(where: { $0.placeId == place.id })?.currency
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    private var listName: String {
        guard let listId = currentPlace.listId,
              let list = store.lists.first(where: { $0.id == listId }) else {
            return "No list"
        }
        return list.title
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            Button {
                Task { await store.setVisited(currentPlace, visited: !currentPlace.isVisited) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: currentPlace.isVisited ? "checkmark.circle.fill" : "circle")
                        .font(.ligga(.title3, weight: .semibold))
                        .foregroundStyle(currentPlace.isVisited ? WandererTheme.mint : WandererTheme.muted)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Visited")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                        Text(currentPlace.isVisited ? "Marked as visited" : "Mark this stop once you've been")
                            .font(.ligga(.caption))
                            .foregroundStyle(WandererTheme.muted)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-visited-toggle")

            Divider().overlay(WandererTheme.line)

            Button {
                costAmount = placeCost > 0 ? String(format: "%.2f", placeCost) : ""
                showCostPrompt = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "banknote")
                        .font(.ligga(.body, weight: .semibold))
                        .foregroundStyle(WandererTheme.coralDeep)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cost")
                            .font(.ligga(.subheadline, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                        Text(placeCost > 0
                             ? "\(costCurrency) \(String(format: "%.2f", placeCost)) recorded"
                             : "Add what this stop cost")
                            .font(.ligga(.caption))
                            .foregroundStyle(WandererTheme.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "plus.circle")
                        .font(.ligga(.body, weight: .semibold))
                        .foregroundStyle(WandererTheme.coralDeep)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-cost-add")

            if !store.lists.isEmpty {
                Divider().overlay(WandererTheme.line)

                Menu {
                    Button("No list") {
                        Task { await store.assign(currentPlace, toList: nil) }
                    }
                    ForEach(store.lists) { list in
                        Button(list.title) {
                            Task { await store.assign(currentPlace, toList: list.id) }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet")
                            .font(.ligga(.body, weight: .semibold))
                            .foregroundStyle(WandererTheme.ink)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("List")
                                .font(.ligga(.subheadline, weight: .semibold))
                                .foregroundStyle(WandererTheme.ink)
                            Text(listName)
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.ligga(.caption, weight: .semibold))
                            .foregroundStyle(WandererTheme.muted)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("place-list-menu")
            }
        }
        .padding(.horizontal, 16)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func addCost() {
        guard let amount = Double(costAmount.replacingOccurrences(of: ",", with: ".")), amount > 0 else {
            costAmount = ""
            return
        }
        let target = currentPlace
        let currency = costCurrency
        costAmount = ""
        Task { await store.addCost(for: target, amount: amount, currency: currency) }
    }

    // MARK: - Links

    private var linksCard: some View {
        VStack(spacing: 0) {
            if let websiteURL {
                Link(destination: websiteURL) {
                    linkRow(
                        icon: "globe",
                        title: websiteURL.host ?? websiteURL.absoluteString,
                        subtitle: "Website"
                    )
                }

                if phoneURL != nil {
                    Divider()
                        .overlay(WandererTheme.line)
                }
            }

            if let phoneURL {
                Link(destination: phoneURL) {
                    linkRow(
                        icon: "phone.fill",
                        title: place.phone ?? "Call",
                        subtitle: "Phone"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func linkRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(WandererTheme.sandDeep.opacity(0.6))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
            }

            Spacer(minLength: 6)

            Image(systemName: "arrow.up.right")
                .font(.ligga(.footnote, weight: .bold))
                .foregroundStyle(WandererTheme.coralDeep)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            PrimaryButton(
                title: isSaving ? "Saving…" : (isPrivateStop ? "Save private stop" : "Save for everyone"),
                icon: "checkmark",
                isEnabled: !isSaving && !isDeleting
            ) {
                Task { await save() }
            }
            .accessibilityIdentifier("place-save")

            if !isPrivateStop && !LocalTrips.isActive {
                Button {
                    Task { await saveForMe() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Save for me only")
                            .font(.ligga(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(WandererTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        WandererTheme.sandDeep.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDeleting || isSaving)
                .accessibilityIdentifier("place-save-for-me")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isDeleting ? "Removing…" : (isPrivateStop ? "Remove private stop" : "Remove place"))
                        .font(.ligga(.subheadline, weight: .semibold))
                }
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    WandererTheme.coralSoft.opacity(0.75),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting || isSaving)
            .accessibilityIdentifier("place-delete")
        }
        .padding(.top, 2)
    }

    // MARK: - Links helpers

    private var websiteURL: URL? {
        guard var raw = place.website?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let lowercased = raw.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            raw = "https://" + raw
        }
        return URL(string: raw)
    }

    private var phoneURL: URL? {
        guard let phone = place.phone else { return nil }
        let allowed = phone.filter { $0.isNumber || $0 == "+" }
        guard !allowed.isEmpty else { return nil }
        return URL(string: "tel://\(allowed)")
    }

    // MARK: - Saving

    private func save() async {
        guard !isSaving else { return }
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        await store.updatePlace(
            currentPlace,
            name: trimmedName.isEmpty ? currentPlace.name : trimmedName,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            category: category
        )

        isSaving = false
        dismiss()
    }

    /// Saves the same fields as a replacement only this member sees.
    private func saveForMe() async {
        guard !isSaving else { return }
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        await store.updateForMe(
            currentPlace,
            name: trimmedName.isEmpty ? currentPlace.name : trimmedName,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            category: category
        )

        isSaving = false
        dismiss()
    }

    private func remove() async {
        guard !isDeleting else { return }
        isDeleting = true

        await store.deletePlace(place)

        isDeleting = false
        dismiss()
    }
}

#Preview {
    PlaceDetailSheet(
        place: PlaceRecord(
            id: UUID(),
            tripId: UUID(),
            dayId: nil,
            name: "Nishiki Market",
            address: "Nishiki Market, Kyoto, Japan",
            lat: 35.005,
            lng: 135.7649,
            category: .food,
            notes: "Go early, before the crowds. Try the tamagoyaki.",
            website: "https://www.kyoto-nishiki.or.jp",
            phone: "+81 75 211 3882",
            priceLevel: 2,
            rating: 4.5,
            photoUrl: nil,
            startTime: nil,
            endTime: nil,
            position: 0,
            createdBy: nil
        ),
        store: TripDetailStore(trip: Trip.samples[0])
    )
}
