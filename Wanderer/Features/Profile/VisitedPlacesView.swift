import SwiftUI

struct VisitedPlacesView: View {
    @ObservedObject var store: VisitedStore
    @State private var showAddSheet = false
    @State private var addedCount = 0
    @State private var deletedCount = 0

    private let gutter: CGFloat = 16

    private var placeCountLabel: String {
        "\(store.visited.count) \(store.visited.count == 1 ? "place" : "places")"
    }

    private var sortedPlaces: [VisitedPlaceRecord] {
        store.visited.sorted { lhs, rhs in
            let left = CountryOption.name(for: lhs.countryCode)
            let right = CountryOption.name(for: rhs.countryCode)
            if left != right { return left.localizedCompare(right) == .orderedAscending }
            return (lhs.year ?? 0) > (rhs.year ?? 0)
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 6, leading: gutter, bottom: 6, trailing: gutter)
    }

    var body: some View {
        List {
            summaryCard
                .listRowInsets(EdgeInsets(top: 8, leading: gutter, bottom: 16, trailing: gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            SectionHeader(title: "Places you've been", subtitle: placeCountLabel)
                .listRowInsets(EdgeInsets(top: 4, leading: gutter, bottom: 4, trailing: gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if store.visited.isEmpty {
                if store.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(WandererTheme.coral)
                        Text("Loading your map…")
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    emptyState
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(sortedPlaces) { place in
                    VisitedPlaceRow(place: place)
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(place)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(place)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }

            if let message = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(WandererTheme.coralDeep)
                    Text(message)
                        .foregroundStyle(WandererTheme.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.ligga(.caption))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WandererTheme.coralSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: gutter, bottom: 8, trailing: gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Color.clear
                .frame(height: 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WandererTheme.sand.ignoresSafeArea())
        .navigationTitle("Visited places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.ligga(.body, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .tint(WandererTheme.coralDeep)
                .accessibilityLabel("Add a visited place")
                .accessibilityIdentifier("visited-add-place")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddVisitedPlaceSheet(store: store, onSave: { addedCount += 1 })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.success, trigger: addedCount)
        .sensoryFeedback(.impact(weight: .light), trigger: deletedCount)
        .refreshable { await store.load() }
        .task {
            await store.load()
        }
    }

    private func delete(_ place: VisitedPlaceRecord) {
        deletedCount += 1
        Task { await store.delete(place) }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR WORLD SO FAR")
                .font(.ligga(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                stat(value: "\(store.countryCount)", label: store.countryCount == 1 ? "country" : "countries")
                stat(value: "\(store.cityCount)", label: store.cityCount == 1 ? "city" : "cities")
                if let earliest = store.earliestYear {
                    stat(value: String(earliest), label: "first trip")
                }
            }

            if store.countryCodes.isEmpty {
                Text("Every place you add plants a flag here.")
                    .font(.ligga(.footnote))
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                VisitedFlagStrip(codes: store.countryCodes, style: .onDark)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                WandererTheme.charcoal
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 150))
                    .foregroundStyle(WandererTheme.desert.opacity(0.14))
                    .offset(x: 36, y: -24)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        .shadow(color: WandererTheme.shadow, radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.ligga(.title, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.ligga(.caption))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(WandererTheme.coralSoft)
                Image(systemName: "mappin.and.ellipse")
                    .font(.ligga(.title3, weight: .semibold))
                    .foregroundStyle(WandererTheme.coralDeep)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text("No places yet")
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
            Text("Add the first country you've wandered. Cities and years are optional.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showAddSheet = true
            } label: {
                Label("Add a place", systemImage: "plus")
                    .font(.ligga(.subheadline, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(WandererTheme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .liggaCard()
    }
}

// MARK: - Flags

/// A wrapping wall of emoji flags for visited countries, with a "+N" tile when
/// `maxVisible` cuts the list short. Used by the Visited hero and Profile.
struct VisitedFlagStrip: View {
    enum Style {
        case onLight
        case onDark
    }

    let codes: [String]
    var maxVisible: Int? = nil
    var style: Style = .onLight

    @ScaledMetric(relativeTo: .title2) private var tileSize: CGFloat = 40

    private var visible: [String] {
        guard let maxVisible, codes.count > maxVisible else { return codes }
        return Array(codes.prefix(max(0, maxVisible - 1)))
    }

    private var overflow: Int {
        codes.count - visible.count
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize + 8), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(visible, id: \.self) { code in
                Text(CountryOption.emojiFlag(code))
                    .font(.ligga(.title2))
                    .frame(width: tileSize, height: tileSize)
                    .background(tileBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(CountryOption.name(for: code))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.ligga(.subheadline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(style == .onDark ? .white : WandererTheme.ink)
                    .frame(width: tileSize, height: tileSize)
                    .background(tileBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("and \(overflow) more")
            }
        }
    }

    private var tileBackground: Color {
        style == .onDark ? .white.opacity(0.12) : WandererTheme.sand
    }
}

// MARK: - Row

private struct VisitedPlaceRow: View {
    let place: VisitedPlaceRecord

    private var countryName: String {
        CountryOption.name(for: place.countryCode)
    }

    private var trimmedCity: String? {
        guard let city = place.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty else { return nil }
        return city
    }

    private var detailLine: String? {
        let parts = [trimmedCity, place.year.map { String($0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(CountryOption.emojiFlag(place.countryCode))
                .font(.ligga(.largeTitle))
                .frame(width: 48, height: 48)
                .background(WandererTheme.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(countryName)
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)

                if let detailLine {
                    Text(detailLine)
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .liggaCard()
        .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe left or long-press to delete")
    }
}

// MARK: - Add sheet

struct AddVisitedPlaceSheet: View {
    @ObservedObject var store: VisitedStore
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var countryCode = "JP"
    @State private var city = ""
    @State private var yearText = String(Calendar.current.component(.year, from: Date()))

    private var selectedCountry: CountryOption {
        CountryOption.common.first(where: { $0.code == countryCode })
            ?? CountryOption.common[0]
    }

    private var parsedYear: Int? {
        Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        let trimmedYear = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedYear.isEmpty else { return true }
        guard let year = Int(trimmedYear) else { return false }
        return (1900...2100).contains(year)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where have you been?")
                            .font(.ligga(.title2, weight: .bold))
                            .foregroundStyle(WandererTheme.ink)
                        Text("Add a country, and optionally the city and year.")
                            .font(.ligga(.subheadline))
                            .foregroundStyle(WandererTheme.muted)
                    }

                    fieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Country")
                                .font(.ligga(.caption))
                                .foregroundStyle(WandererTheme.muted)

                            Picker("Country", selection: $countryCode) {
                                ForEach(CountryOption.common) { option in
                                    Text("\(option.flag) \(option.name)")
                                        .tag(option.code)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(WandererTheme.ink)
                            .accessibilityIdentifier("visited-country-picker")

                            HStack(spacing: 8) {
                                Text(selectedCountry.flag)
                                    .font(.ligga(.title3))
                                Text(selectedCountry.name)
                                    .font(.ligga(.subheadline))
                                    .foregroundStyle(WandererTheme.ink.opacity(0.75))
                            }
                        }
                    }

                    fieldCard {
                        labeledField("City (optional)", systemImage: "building.2.fill", placeholder: "Kyoto", text: $city)
                        Divider().overlay(WandererTheme.line)
                        labeledField("Year (optional)", systemImage: "calendar", placeholder: "2024", text: $yearText)
                            .keyboardType(.numberPad)
                    }
                }
                .padding(16)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("visited-save")
                }
            }
        }
    }

    private func save() {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedYear = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = trimmedYear.isEmpty ? nil : Int(trimmedYear)

        Task {
            await store.add(
                countryCode: countryCode,
                city: trimmedCity.isEmpty ? nil : trimmedCity,
                year: year
            )
        }
        onSave?()
        dismiss()
    }

    private func fieldCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .liggaCard()
    }

    private func labeledField(_ label: String, systemImage: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.ligga(.caption))
                    .foregroundStyle(WandererTheme.muted)
                TextField(placeholder, text: text)
                    .font(.ligga(.body, weight: .medium))
                    .foregroundStyle(WandererTheme.ink)
            }
        }
    }
}

// MARK: - Country catalog

struct CountryOption: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
    var flag: String { Self.emojiFlag(code) }

    static func emojiFlag(_ code: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in code.uppercased().unicodeScalars {
            if let flagScalar = UnicodeScalar(127397 + scalar.value) {
                scalars.append(flagScalar)
            }
        }
        return String(scalars)
    }

    static func name(for code: String) -> String {
        let upper = code.uppercased()
        if let match = common.first(where: { $0.code == upper }) {
            return match.name
        }
        return Locale.current.localizedString(forRegionCode: upper) ?? upper
    }

    static let common: [CountryOption] = [
        .init(code: "JP", name: "Japan"),
        .init(code: "ID", name: "Indonesia"),
        .init(code: "MY", name: "Malaysia"),
        .init(code: "SG", name: "Singapore"),
        .init(code: "TH", name: "Thailand"),
        .init(code: "VN", name: "Vietnam"),
        .init(code: "PH", name: "Philippines"),
        .init(code: "KR", name: "South Korea"),
        .init(code: "CN", name: "China"),
        .init(code: "IN", name: "India"),
        .init(code: "AU", name: "Australia"),
        .init(code: "NZ", name: "New Zealand"),
        .init(code: "US", name: "United States"),
        .init(code: "CA", name: "Canada"),
        .init(code: "MX", name: "Mexico"),
        .init(code: "BR", name: "Brazil"),
        .init(code: "AR", name: "Argentina"),
        .init(code: "PE", name: "Peru"),
        .init(code: "CL", name: "Chile"),
        .init(code: "CO", name: "Colombia"),
        .init(code: "GB", name: "United Kingdom"),
        .init(code: "IE", name: "Ireland"),
        .init(code: "FR", name: "France"),
        .init(code: "ES", name: "Spain"),
        .init(code: "PT", name: "Portugal"),
        .init(code: "IT", name: "Italy"),
        .init(code: "DE", name: "Germany"),
        .init(code: "NL", name: "Netherlands"),
        .init(code: "BE", name: "Belgium"),
        .init(code: "CH", name: "Switzerland"),
        .init(code: "AT", name: "Austria"),
        .init(code: "GR", name: "Greece"),
        .init(code: "TR", name: "Türkiye"),
        .init(code: "NO", name: "Norway"),
        .init(code: "SE", name: "Sweden"),
        .init(code: "DK", name: "Denmark"),
        .init(code: "FI", name: "Finland"),
        .init(code: "IS", name: "Iceland"),
        .init(code: "PL", name: "Poland"),
        .init(code: "CZ", name: "Czechia"),
        .init(code: "HR", name: "Croatia"),
        .init(code: "MA", name: "Morocco"),
        .init(code: "ZA", name: "South Africa"),
        .init(code: "EG", name: "Egypt"),
        .init(code: "AE", name: "United Arab Emirates"),
        .init(code: "QA", name: "Qatar"),
        .init(code: "IL", name: "Israel"),
        .init(code: "JO", name: "Jordan")
    ]
}

#Preview {
    NavigationStack {
        VisitedPlacesView(store: VisitedStore())
    }
}
