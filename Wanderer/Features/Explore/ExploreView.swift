import SwiftUI

struct ExploreView: View {
    @StateObject private var store = ExploreStore()
    @State private var hasRequested = false
    @State private var query = ""
    @State private var selectedRegion: String?
    @FocusState private var isSearchFocused: Bool

    private let gutter: CGFloat = 16

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        !trimmedQuery.isEmpty || selectedRegion != nil
    }

    /// Destination chips, derived from the last comma part of each published
    /// guide's destination ("Kyoto, Japan" → "Japan"), in first-seen order.
    private var regions: [String] {
        var seen = Set<String>()
        return store.guides.compactMap { GuideFilter.region(for: $0) }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var filteredGuides: [GuideRecord] {
        store.guides.filter { guide in
            GuideFilter.matches(guide, query: trimmedQuery, region: selectedRegion)
        }
    }

    private var featuredGuide: GuideRecord? { store.guides.first }
    private var remainingGuides: [GuideRecord] { Array(store.guides.dropFirst()) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if !store.guides.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            searchField
                            if regions.count > 1 {
                                regionChips
                            }
                        }
                    }

                    if let message = store.errorMessage, !store.guides.isEmpty {
                        errorBanner(message)
                    }

                    content
                }
                .padding(.horizontal, gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
                // A guide row reads best as a column; don't stretch it across
                // the whole inner display.
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(WandererBackdrop())
            .contentMargins(.bottom, 96, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await reload() }
            .sensoryFeedback(.selection, trigger: selectedRegion)
            .task {
                if store.guides.isEmpty {
                    await reload()
                }
                hasRequested = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Explore")
                .font(.display(.largeTitle))
                .foregroundStyle(WandererTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Guides to remix into your own itinerary.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
        }
    }

    // MARK: - Search & filters

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .accessibilityHidden(true)

            TextField("Search guides or places", text: $query)
                .font(.ligga(.body))
                .foregroundStyle(WandererTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .accessibilityIdentifier("explore-search")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ligga(.body))
                        .foregroundStyle(WandererTheme.muted.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 0)
        .frame(minHeight: 48)
        .liggaCard()
    }

    private var regionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedRegion == nil) {
                    selectedRegion = nil
                }
                ForEach(regions, id: \.self) { region in
                    chip(title: region, isSelected: selectedRegion == region) {
                        selectedRegion = selectedRegion == region ? nil : region
                    }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -gutter)
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(isSelected ? WandererTheme.onPrimary : WandererTheme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(isSelected ? WandererTheme.primaryFill : WandererTheme.card, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? .clear : WandererTheme.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if (store.isLoading || !hasRequested) && store.guides.isEmpty && store.errorMessage == nil {
            loadingState
        } else if let message = store.errorMessage, store.guides.isEmpty {
            errorState(message)
        } else if isFiltering {
            filteredResults
        } else if let featuredGuide {
            NavigationLink {
                GuideDetailView(guide: featuredGuide, store: store)
            } label: {
                FeaturedGuideCard(guide: featuredGuide)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("explore-guide-0")

            if remainingGuides.isEmpty {
                VStack(spacing: 6) {
                    Text("More guides are on the way")
                        .font(.ligga(.headline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                    Text("Every published guide will show up here.")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                SectionHeader(
                    title: "More guides",
                    subtitle: "\(remainingGuides.count) \(remainingGuides.count == 1 ? "guide" : "guides") to wander through"
                )
                .padding(.top, 4)

                guideList(remainingGuides, identifierOffset: 1)
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var filteredResults: some View {
        let results = filteredGuides
        if results.isEmpty {
            noResultsState
        } else {
            SectionHeader(
                title: selectedRegion ?? "Results",
                subtitle: "\(results.count) \(results.count == 1 ? "guide" : "guides")"
                    + (trimmedQuery.isEmpty ? "" : " for “\(trimmedQuery)”")
            )
            guideList(results, identifierOffset: 0)
        }
    }

    private func guideList(_ guides: [GuideRecord], identifierOffset: Int) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(guides.enumerated()), id: \.element.id) { item in
                NavigationLink {
                    GuideDetailView(guide: item.element, store: store)
                } label: {
                    GuideRow(guide: item.element)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("explore-guide-\(item.offset + identifierOffset)")
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous)
                .fill(WandererTheme.sandDeep.opacity(0.6))
                .frame(height: 250)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous)
                    .fill(WandererTheme.card)
                    .frame(height: 92)
            }
            Text("Gathering guides…")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading guides")
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            stateBadge(systemImage: "magnifyingglass")

            Text("No guides match")
                .font(.ligga(.title3, weight: .bold))
                .foregroundStyle(WandererTheme.ink)

            Text(noResultsMessage)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)

            Button {
                query = ""
                selectedRegion = nil
                isSearchFocused = false
            } label: {
                Text("Clear filters")
                    .font(.ligga(.subheadline, weight: .bold))
                    .foregroundStyle(WandererTheme.onPrimary)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(WandererTheme.primaryFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .liggaCard()
        .accessibilityIdentifier("explore-no-results")
    }

    private var noResultsMessage: String {
        switch (trimmedQuery.isEmpty, selectedRegion) {
        case (false, .some(let region)):
            return "Nothing in \(region) mentions “\(trimmedQuery)”. Try another word or show all destinations."
        case (false, .none):
            return "Nothing mentions “\(trimmedQuery)” yet. Try a city, country or a word like coffee."
        case (true, .some(let region)):
            return "There are no guides for \(region) yet."
        case (true, .none):
            return "Try a different search."
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            stateBadge(systemImage: "safari.fill")

            Text("No guides published yet")
                .font(.ligga(.title3, weight: .bold))
                .foregroundStyle(WandererTheme.ink)

            Text("Curated routes will show up here. Pull down to check again, or plan your own trip from the Trips tab.")
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            retryButton
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            stateBadge(systemImage: "exclamationmark.triangle.fill")

            Text("Guides are out of reach")
                .font(.ligga(.title3, weight: .bold))
                .foregroundStyle(WandererTheme.ink)

            Text(message)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            retryButton
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    private func stateBadge(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(WandererTheme.coralSoft)
            Image(systemName: systemImage)
                .font(.ligga(.title2, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
            Text(message)
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.ink.opacity(0.8))
                .lineLimit(3)
            Spacer(minLength: 6)
            Button("Retry") {
                Task { await reload() }
            }
            .font(.ligga(.caption, weight: .bold))
            .foregroundStyle(WandererTheme.coralDeep)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(WandererTheme.coralSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var retryButton: some View {
        Button {
            Task { await reload() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.clockwise")
                Text("Try again")
            }
            .font(.ligga(.subheadline, weight: .bold))
            .foregroundStyle(WandererTheme.onPrimary)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(WandererTheme.primaryFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        store.errorMessage = nil
        await store.load()
    }
}

// MARK: - Filtering

enum GuideFilter {
    static func region(for guide: GuideRecord) -> String? {
        guard let destination = guide.destination else { return nil }
        let last = destination.split(separator: ",").last.map(String.init) ?? destination
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func matches(_ guide: GuideRecord, query: String, region: String?) -> Bool {
        if let region, Self.region(for: guide)?.caseInsensitiveCompare(region) != .orderedSame {
            return false
        }
        guard !query.isEmpty else { return true }
        let haystack = [guide.title, guide.destination ?? "", guide.summary ?? ""].joined(separator: " ")
        return query
            .split(whereSeparator: \.isWhitespace)
            .allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

// MARK: - Cards

private struct FeaturedGuideCard: View {
    let guide: GuideRecord
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // A flexible clear base sets the size; the photo fills it without
            // pushing its own (much wider) image size onto the layout.
            Color.clear
                .overlay { GuideCoverImage(guide: guide) }
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: WandererTheme.charcoal.opacity(0.92), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("Featured guide")
                    .font(.ligga(.footnote, weight: .bold))
                    .foregroundStyle(Color(hex: 0x10283A))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: 0xF2A922), in: Capsule())
                    .padding(.bottom, 4)

                Text(guide.title)
                    .font(.display(.title2))
                    .foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)

                if let summary = guide.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.ligga(.footnote))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 5 : 2)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 280, alignment: .leading)
                }

                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                    Text(guide.destination ?? "Curated route")
                }
                .font(.ligga(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        // Grows with large text instead of cutting the title off.
        .frame(minHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: WandererTheme.postcardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Featured guide: \(guide.title), \(guide.destination ?? "curated route")")
        .accessibilityAddTraits(.isButton)
    }
}

private struct GuideRow: View {
    let guide: GuideRecord

    var body: some View {
        HStack(spacing: 14) {
            GuideCoverImage(guide: guide)
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title)
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)

                if let destination = guide.destination, !destination.isEmpty {
                    Label(destination, systemImage: "mappin")
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                }

                if let summary = guide.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.ligga(.caption, weight: .bold))
                .foregroundStyle(WandererTheme.muted.opacity(0.55))
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: 68)
        .liggaCard()
        .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Resolves a guide's cover: its own `cover_url` first, then a curated
/// destination photo, with a warm gradient fallback while loading or on failure.
struct GuideCoverImage: View {
    let guide: GuideRecord

    var body: some View {
        AsyncImage(url: coverURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallback
            case .empty:
                ZStack {
                    fallback
                    ProgressView()
                        .tint(.white)
                }
            @unknown default:
                fallback
            }
        }
    }

    private var coverURL: URL? {
        if let coverUrl = guide.coverUrl,
           !coverUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: coverUrl) {
            return url
        }
        return ImageCatalog.cover(for: guide.destination ?? guide.title)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [WandererTheme.plum, WandererTheme.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "map.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white.opacity(0.16))
        }
    }
}

#Preview {
    ExploreView()
}
