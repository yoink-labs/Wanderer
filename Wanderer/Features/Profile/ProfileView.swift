import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var visitedStore = VisitedStore()

    @AppStorage("wanderer.selectedLanguage") private var storedLanguage = "en"
    @AppStorage("wanderer.isGuest") private var isGuest = false
    @AppStorage("wanderer.currency") private var currency = "USD"
    @AppStorage("wanderer.units") private var units = "Metric"
    @AppStorage("wanderer.appearance") private var appearanceRaw = WandererAppearance.system.rawValue

    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var didApplyRemoteSettings = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarSavedCount = 0
    @State private var avatarFailedCount = 0

    private let gutter: CGFloat = 16

    private let currencyCodes = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD"]
    private let unitOptions = ["Metric", "Imperial"]

    private var language: LanguageOption {
        LanguageOption.named(storedLanguage)
    }

    private var profileEmail: String {
        profileStore.profile?.email ?? auth.userEmail
    }

    private var displayName: String {
        if isGuest { return "Guest traveller" }
        if let name = profileStore.profile?.displayName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        guard let prefix = profileEmail.split(separator: "@").first, !prefix.isEmpty else {
            return "Traveller"
        }
        return prefix
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var initials: String {
        if isGuest { return "GT" }
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "LG" : String(letters).uppercased()
    }

    private var emailLine: String {
        if isGuest { return "Not signed in" }
        return profileEmail.isEmpty ? "Signed in" : profileEmail
    }

    private var visitedSummary: String {
        "\(countLabel(visitedStore.countryCount, singular: "country", plural: "countries")), "
            + "\(countLabel(visitedStore.cityCount, singular: "city", plural: "cities"))"
    }

    private var appearance: WandererAppearance {
        WandererAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var unitsLabel: String {
        switch units.lowercased() {
        case "metric": return "Metric"
        case "imperial": return "Imperial"
        default: return units.capitalized
        }
    }

    private var canEditAvatar: Bool {
        !isGuest && profileStore.profile != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("Profile")
                        .font(.display(.largeTitle))
                        .foregroundStyle(WandererTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    if isGuest {
                        guestCard
                    } else {
                        profileCard
                        statsCard
                        visitedCard
                    }
                    settingsCard

                    if !isGuest, let message = profileStore.errorMessage ?? visitedStore.errorMessage {
                        errorNote(message)
                    }

                    if !isGuest {
                        signOutButton
                    }

                if canDeleteAccount {
                    deleteAccountButton
                }
                }
                .padding(.horizontal, gutter)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(WandererTheme.sand.ignoresSafeArea())
            .contentMargins(.bottom, 96, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadAll() }
        }
        .sensoryFeedback(.success, trigger: avatarSavedCount)
        .sensoryFeedback(.error, trigger: avatarFailedCount)
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(from: item) }
        }
        .task {
            await loadAll()
            applyRemoteSettingsIfNeeded()
        }
    }

    private func loadAll() async {
        // Guests have no account to load; their trips live on the device.
        guard !isGuest, auth.isAuthenticated else { return }
        await profileStore.load()
        await visitedStore.load()
        await profileStore.loadTripCount()
    }

    private func uploadAvatar(from item: PhotosPickerItem) async {
        defer { avatarItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = AvatarImageEncoder.jpegData(from: data) else {
            profileStore.errorMessage = "That photo couldn't be read. Try another one."
            avatarFailedCount += 1
            return
        }
        if await profileStore.updateAvatar(imageData: jpeg) {
            avatarSavedCount += 1
        } else {
            avatarFailedCount += 1
        }
    }

    // MARK: - Guest

    /// Guests get one clear next step instead of empty account stats: their
    /// trips are safe on this phone, and an account carries them everywhere.
    private var guestCard: some View {
        let tripCount = GuestTripsStore.load().count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WandererMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Planning as a guest")
                        .font(.display(.title3))
                        .foregroundStyle(.white)
                    Text(tripCount == 0
                         ? "Trips you plan stay on this phone"
                         : "\(tripCount.liggaCounted("trip")) saved on this phone")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Text("Make a free Yoink Labs account to keep your trips on every device and plan with friends. Everything you've planned comes with you.")
                .font(.ligga(.subheadline))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                LiggaHaptics.tap()
                withAnimation { isGuest = false }
            } label: {
                Text("Create a free account")
                    .font(.ligga(.headline, weight: .bold))
                    .foregroundStyle(Color(hex: 0x10283A))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Color(hex: 0xF2A922), in: RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous))
            }
            .buttonStyle(.liggaPressable)
            .accessibilityIdentifier("profile-guest-create-account")

            Button("I already have an account") {
                withAnimation { isGuest = false }
            }
            .font(.ligga(.subheadline, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(20)
        .background(Color(hex: 0x10283A), in: RoundedRectangle(cornerRadius: WandererTheme.postcardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WandererTheme.postcardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var profileCard: some View {
        HStack(spacing: 16) {
            avatarControl

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.ligga(.title2, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(emailLine)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if canEditAvatar {
                    Text(profileStore.profile?.avatarUrl == nil ? "Tap the photo to add one" : "Tap the photo to change it")
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.accentText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liggaCard()
    }

    @ViewBuilder
    private var avatarControl: some View {
        let avatar = ProfileAvatarView(
            avatarURL: profileStore.profile?.avatarUrl,
            initials: initials,
            size: 64
        )
        .overlay {
            if profileStore.isUploadingAvatar {
                ZStack {
                    Circle().fill(WandererTheme.charcoal.opacity(0.45))
                    ProgressView().tint(.white)
                }
            }
        }

        if canEditAvatar {
            PhotosPicker(selection: $avatarItem, matching: .images) {
                avatar
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.ligga(.caption2, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(WandererTheme.ink, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(profileStore.isUploadingAvatar)
            .accessibilityLabel(profileStore.profile?.avatarUrl == nil ? "Add profile photo" : "Change profile photo")
            .accessibilityIdentifier("profile-avatar-picker")
        } else {
            avatar
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statTile(count: visitedStore.countryCount, label: visitedStore.countryCount == 1 ? "country" : "countries")
            statDivider
            statTile(count: visitedStore.cityCount, label: visitedStore.cityCount == 1 ? "city" : "cities")
            if let tripCount = profileStore.tripCount {
                statDivider
                statTile(count: tripCount, label: tripCount == 1 ? "trip" : "trips")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .liggaCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsAccessibilityLabel)
    }

    private var statsAccessibilityLabel: String {
        var parts = [visitedSummary]
        if let tripCount = profileStore.tripCount {
            parts.append(countLabel(tripCount, singular: "trip", plural: "trips"))
        }
        return parts.joined(separator: ", ")
    }

    private var statDivider: some View {
        Rectangle().fill(WandererTheme.line).frame(width: 1, height: 40)
    }

    private func statTile(count: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.ligga(.title, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WandererTheme.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.ligga(.footnote))
                .foregroundStyle(WandererTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Visited

    private var visitedCard: some View {
        NavigationLink {
            VisitedPlacesView(store: visitedStore)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Visited places")
                        .font(.ligga(.headline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(visitedStore.visited.isEmpty ? "Add" : "View all")
                        Image(systemName: "chevron.right")
                            .font(.ligga(.caption, weight: .bold))
                    }
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.accentText)
                }

                if visitedStore.countryCodes.isEmpty {
                    Text(visitedStore.isLoading ? "Loading your map…" : "Log the countries you've been to and watch your map fill in.")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VisitedFlagStrip(codes: visitedStore.countryCodes, maxVisible: 8)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liggaCard()
            .contentShape(RoundedRectangle(cornerRadius: WandererTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visited places, \(visitedSummary)")
        .accessibilityIdentifier("profile-visited-places")
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Menu {
                languageMenuContent
            } label: {
                settingsRow(title: "Language", value: language.nativeName, icon: "globe")
            }
            .buttonStyle(.plain)

            cardDivider

            Menu {
                currencyMenuContent
            } label: {
                settingsRow(title: "Currency", value: currency, icon: "banknote")
            }
            .buttonStyle(.plain)

            cardDivider

            Menu {
                unitsMenuContent
            } label: {
                settingsRow(title: "Units", value: unitsLabel, icon: "ruler")
            }
            .buttonStyle(.plain)

            cardDivider

            Menu {
                appearanceMenuContent
            } label: {
                settingsRow(title: "Appearance", value: appearance.title, icon: "circle.lefthalf.filled")
            }
            .buttonStyle(.plain)

        }
        .liggaCard()
    }

    @ViewBuilder
    private var appearanceMenuContent: some View {
        ForEach(WandererAppearance.allCases) { option in
            Button {
                appearanceRaw = option.rawValue
            } label: {
                if option == appearance {
                    Label(option.title, systemImage: "checkmark")
                } else {
                    Text(option.title)
                }
            }
        }
    }

    private var languageMenuContent: some View {
        ForEach(LanguageOption.all) { option in
            Button {
                storedLanguage = option.id
                didApplyRemoteSettings = true
                persistSettings(locale: option.id)
            } label: {
                Text("\(option.nativeName) · \(option.englishName)")
            }
        }
    }

    @ViewBuilder
    private var currencyMenuContent: some View {
        ForEach(currencyCodes, id: \.self) { code in
            Button {
                currency = code
                didApplyRemoteSettings = true
                persistSettings(newCurrency: code)
            } label: {
                Text(code)
            }
        }
    }

    @ViewBuilder
    private var unitsMenuContent: some View {
        ForEach(unitOptions, id: \.self) { option in
            Button {
                units = option
                didApplyRemoteSettings = true
                persistSettings(newUnits: option)
            } label: {
                Text(option)
            }
        }
    }

    private var cardDivider: some View {
        Divider()
            .overlay(WandererTheme.line)
            .padding(.leading, 55)
    }

    private func settingsRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.ligga(.body, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .frame(width: 26)
                .accessibilityHidden(true)

            Text(title)
                .font(.ligga(.body, weight: .medium))
                .foregroundStyle(WandererTheme.ink)

            Spacer()

            Text(value)
                .font(.ligga(.subheadline))
                .foregroundStyle(WandererTheme.muted)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.ligga(.caption2, weight: .bold))
                .foregroundStyle(WandererTheme.muted.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private func errorNote(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ligga(.footnote, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
            Text(message)
                .font(.ligga(.caption))
                .foregroundStyle(WandererTheme.muted)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WandererTheme.coralSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var signOutButton: some View {
        Button {
            Task {
                await auth.signOut()
                withAnimation {
                    isGuest = false
                }
            }
        } label: {
            Text(isGuest ? "Exit guest mode" : "Sign out")
                .font(.ligga(.headline, weight: .semibold))
                .foregroundStyle(WandererTheme.coralDeep)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WandererTheme.coralSoft, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var canDeleteAccount: Bool {
        !isGuest && auth.isAuthenticated
    }

    /// The Worker's delete endpoint removes the account's trips and media.
    private var deleteAccountButton: some View {
        Button(role: .destructive) {
            showDeleteAccountConfirm = true
        } label: {
            Group {
                if isDeletingAccount {
                    ProgressView().tint(WandererTheme.coralDeep)
                } else {
                    Text("Delete account")
                        .font(.ligga(.subheadline, weight: .semibold))
                }
            }
            .foregroundStyle(WandererTheme.coralDeep)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isDeletingAccount)
        .confirmationDialog(
            "Delete your Wanderer account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account and all trips", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    defer { isDeletingAccount = false }
                    do {
                        try await CloudSession.shared.api?.deleteAccount()
                        await auth.signOut()
                    } catch {
                        profileStore.errorMessage = "Couldn't delete the account: \(error.localizedDescription)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your trips, places, bookings, expenses and files. It cannot be undone.")
        }
    }

    // MARK: - Helpers

    private func persistSettings(locale: String? = nil, newCurrency: String? = nil, newUnits: String? = nil) {
        let localeValue = locale ?? storedLanguage
        let currencyValue = newCurrency ?? currency
        let unitsValue = newUnits ?? units

        Task {
            await profileStore.update(locale: localeValue, currency: currencyValue, units: unitsValue)
        }
    }

    private func applyRemoteSettingsIfNeeded() {
        guard !didApplyRemoteSettings, let profile = profileStore.profile else { return }
        didApplyRemoteSettings = true
        if !profile.locale.isEmpty {
            storedLanguage = profile.locale
        }
        if !profile.currency.isEmpty {
            currency = profile.currency
        }
        if !profile.units.isEmpty {
            units = profile.units
        }
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthStore())
}
