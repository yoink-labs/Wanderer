import Foundation
import SwiftUI
import UIKit

struct ShareTripView: View {
    let trip: Trip
    /// Member profiles already loaded by the trip store; used for names.
    var profiles: [TripMemberProfile] = []
    /// The signed-in member's internal profile id, for "you" in balances.
    var currentUserId: UUID?

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ShareStore()

    @State private var copied = false
    @State private var inviteEmail = ""
    @State private var delivery: InviteDelivery?
    @State private var inviteError: String?
    @FocusState private var emailFocused: Bool

    @AppStorage("wanderer.isGuest") private var isGuest = false
    @State private var confirmReset = false
    @State private var linkReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The public, read-only page for this trip on api.yoinklabs.dev.
    private var shareURL: URL? {
        store.shareToken.flatMap { store.shareURL(for: $0) }
    }

    /// Short, readable form of the link; the full URL is what's copied.
    private var displayLink: String {
        guard let shareURL else { return "" }
        let text = (shareURL.host() ?? "") + shareURL.path()
        return text.count > 34 ? String(text.prefix(33)) + "…" : text
    }

    private var ownerDisplayName: String {
        let email = auth.userEmail.tripToolsTrimmed
        return email.isEmpty ? "You" : email
    }

    private var canInvite: Bool {
        let email = inviteEmail.tripToolsTrimmed
        guard delivery?.isSending != true else { return false }
        return email.contains("@") && email.contains(".") && !email.contains(" ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if !store.isAvailable {
                    guestCard
                } else {
                    if shareURL != nil {
                        linkCard
                    }

                    TripToolGroupLabel(title: "People", trailing: people.isEmpty ? nil : "\(people.count)")
                    peopleCard

                    TripToolGroupLabel(title: "Invite by email")
                    inviteCard
                }
            }
            .padding(.horizontal, TripToolsLayout.gutter)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WandererTheme.platinum.ignoresSafeArea())
        .task {
            store.setInitialToken(trip.shareToken)
            await store.load(tripID: trip.id)
        }
        .onChange(of: store.errorMessage) { _, message in
            if let message {
                inviteError = message
                store.errorMessage = nil
            }
        }
        .confirmationDialog("Make a new link?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Make a new link", role: .destructive) {
                Task {
                    await store.resetLink(tripID: trip.id)
                    LiggaHaptics.success()
                    withAnimation(WandererMotion.animation(WandererMotion.snappy, reduceMotion: reduceMotion)) {
                        linkReset = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current link stops working for everyone who has it.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { inviteError != nil },
            set: { if !$0 { inviteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteError ?? "")
        }
    }

    // MARK: - Guest

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "person.2.fill")
                .font(.ligga(.title2, weight: .bold))
                .foregroundStyle(Color(hex: 0xF2A922))
                .accessibilityHidden(true)
            Text("Plan this trip together")
                .wandererHeading(.section)
                .foregroundStyle(.white)
            Text("Sharing a link and inviting people need a free Yoink Labs account. Everything you've planned on this phone comes with you.")
                .font(.ligga(.subheadline))
                .foregroundStyle(.white.opacity(0.88))
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
            .accessibilityIdentifier("share-guest-create-account")
            Text("You can still send the itinerary as a PDF with the share button at the top.")
                .font(.ligga(.footnote))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x10283A), in: RoundedRectangle(cornerRadius: WandererTheme.postcardRadius, style: .continuous))
    }

    // MARK: - People

    private struct Person: Identifiable {
        let id: String
        let name: String
        let detail: String
        let badge: String
        let initials: String
        let isPending: Bool
    }

    private var people: [Person] {
        var result: [Person] = []
        var seen = Set<UUID>()

        // Prefer the share store's membership rows (they carry roles even
        // when profiles are missing); fall back to the trip store's profiles.
        let roles: [(UUID, TripRole)] = store.members.isEmpty
            ? profiles.map { ($0.userId, $0.role) }
            : store.members.map { ($0.userId, $0.role) }

        for (userId, role) in roles where !seen.contains(userId) {
            seen.insert(userId)
            let profile = profiles.first { $0.userId == userId }
            let isYou = userId == currentUserId
            let name = isYou ? "You" : (profile?.displayName ?? "Trip member")
            let email = isYou ? ownerDisplayName : profile?.profiles?.email
            result.append(Person(
                id: userId.uuidString,
                name: name,
                detail: [email, role == .viewer ? "Can view" : "Can edit"]
                    .compactMap { $0?.tripToolsNilIfEmpty }
                    .filter { $0 != name }
                    .joined(separator: " · "),
                badge: role.title,
                initials: isYou ? initials(from: ownerDisplayName) : (profile?.initials ?? "TM"),
                isPending: false
            ))
        }

        if result.isEmpty, currentUserId != nil {
            result.append(Person(
                id: "me",
                name: "You",
                detail: ownerDisplayName == "You" ? "Can edit" : "\(ownerDisplayName) · Can edit",
                badge: TripRole.owner.title,
                initials: initials(from: ownerDisplayName),
                isPending: false
            ))
        }

        let memberEmails = Set(profiles.compactMap { $0.profiles?.email?.lowercased() })
        for invite in store.invites where invite.acceptedAt == nil && !memberEmails.contains(invite.email.lowercased()) {
            result.append(Person(
                id: invite.id.uuidString,
                name: invite.email,
                detail: "Invite pending · \(invite.role == .viewer ? "Can view" : "Can edit")",
                badge: "Invited",
                initials: "",
                isPending: true
            ))
        }
        return result
    }

    private func initials(from value: String) -> String {
        let prefix = value.split(separator: "@").first.map(String.init) ?? ""
        let letters = prefix.split(whereSeparator: { $0 == "." || $0 == " " || $0 == "_" }).prefix(2).compactMap(\.first)
        if letters.count == 2 { return String(letters).uppercased() }
        return prefix.isEmpty ? "ME" : String(prefix.prefix(2)).uppercased()
    }

    private var peopleCard: some View {
        VStack(spacing: 0) {
            if people.isEmpty {
                HStack(spacing: 10) {
                    if store.isLoading {
                        ProgressView()
                    }
                    Text(store.isLoading ? "Loading people…" : "Sign in to see who's on this trip.")
                        .font(.ligga(.subheadline))
                        .foregroundStyle(WandererTheme.muted)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 14)
            }

            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    Divider().overlay(WandererTheme.line).padding(.leading, 66)
                }
                personRow(person)
            }
        }
        .liggaCard()
    }

    private func personRow(_ person: Person) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(WandererTheme.platinum)
                if person.isPending {
                    Image(systemName: "envelope")
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.muted)
                } else {
                    Text(person.initials)
                        .font(.ligga(.caption, weight: .bold))
                        .foregroundStyle(WandererTheme.ink)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !person.detail.isEmpty {
                    Text(person.detail)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            Text(person.badge)
                .font(.ligga(.caption2, weight: .semibold))
                .foregroundStyle(WandererTheme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(WandererTheme.platinum, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Invite

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("friend@example.com", text: $inviteEmail)
                .font(.ligga(.body))
                .foregroundStyle(WandererTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .submitLabel(.send)
                .onSubmit(sendInvite)
                .focused($emailFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(WandererTheme.platinum, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Email address to invite")
                .accessibilityIdentifier("share-invite-email")

            TripToolPrimaryButton(
                title: delivery?.isSending == true ? "Sending…" : "Send invite",
                icon: "paperplane",
                isEnabled: canInvite
            ) {
                sendInvite()
            }
            .accessibilityIdentifier("share-send-invite")

            if let delivery {
                deliveryStatus(delivery)
            } else {
                Text("They get edit access once they sign in with this email.")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .liggaCard()
    }

    @ViewBuilder
    private func deliveryStatus(_ delivery: InviteDelivery) -> some View {
        switch delivery {
        case .sending(let email):
            HStack(spacing: 8) {
                ProgressView()
                Text("Saving invite and emailing \(email)…")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
            }
            .accessibilityElement(children: .combine)

        case .sent(let email):
            Label("Invite emailed to \(email).", systemImage: "checkmark.circle")
                .font(.ligga(.footnote, weight: .medium))
                .foregroundStyle(WandererTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case .notSent(let email):
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Invite saved for \(email), but the email didn't go out. Send it yourself so they know to join.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.ligga(.footnote, weight: .medium))
                .foregroundStyle(WandererTheme.coralDeep)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TripToolSecondaryButton(title: "Open Mail", icon: "envelope") {
                        openMail(to: email)
                    }
                    ShareLink(
                        item: inviteMessage(for: email),
                        subject: Text("Join \(trip.title) on Wanderer")
                    ) {
                        TripToolSecondaryLabel(title: "Share invite", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sendInvite() {
        let email = inviteEmail.tripToolsTrimmed.lowercased()
        guard canInvite else { return }
        emailFocused = false
        delivery = .sending(email)

        Task {
            let saved = await store.invite(tripID: trip.id, email: email)
            guard saved else {
                delivery = nil
                return
            }
            inviteEmail = ""

            let sent = await store.sendInviteEmail(
                trip: trip,
                to: email,
                inviterName: ownerDisplayName
            )
            delivery = sent ? .sent(email) : .notSent(email)
        }
    }

    /// Invites are claimed by signing in with the invited email, so the
    /// message says exactly that; the read-only link is added when there is one.
    private func inviteMessage(for email: String) -> String {
        var text = "I added you to \(trip.title) on Wanderer. Install Wanderer and sign in with \(email), and the trip shows up in your Trips."
        if let shareURL {
            text += "\n\nPreview the plan: \(shareURL.absoluteString)"
        }
        return text
    }

    private func openMail(to email: String) {
        let subject = "Join my trip on Wanderer: \(trip.title)"
        let body = inviteMessage(for: email)
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }
        openURL(url)
    }

    // MARK: - Link

    /// The read-only link, first because it's the quickest way to share.
    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link")
                    .font(.ligga(.headline, weight: .bold))
                    .foregroundStyle(WandererTheme.onAccent)
                    .frame(width: 36, height: 36)
                    .background(WandererTheme.route, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anyone with the link can view the plan")
                        .wandererHeading(.card)
                        .foregroundStyle(WandererTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Days and stops only. People, notes, costs, bookings and files stay private.")
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(verbatim: displayLink)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(WandererTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(WandererTheme.fillMuted, in: RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous))
                .accessibilityLabel("Trip link")
                .accessibilityValue(shareURL?.absoluteString ?? "")

            if linkReset {
                Label("New link made. The old one no longer works.", systemImage: "checkmark.circle.fill")
                    .font(.ligga(.footnote, weight: .semibold))
                    .foregroundStyle(WandererTheme.lagoon)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                TripToolSecondaryButton(
                    title: copied ? "Copied" : "Copy link",
                    icon: copied ? "checkmark" : "doc.on.doc"
                ) {
                    copyLink()
                }
                .accessibilityIdentifier("share-copy-link")

                if let shareURL {
                    ShareLink(
                        item: shareURL,
                        subject: Text(trip.title),
                        message: Text("Here's the plan for \(trip.title).")
                    ) {
                        TripToolSecondaryLabel(title: "Share", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("share-link")
                }
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in new }

            Button {
                confirmReset = true
            } label: {
                Text(store.isResettingLink ? "Making a new link…" : "Make a new link")
                    .font(.ligga(.subheadline, weight: .semibold))
                    .foregroundStyle(WandererTheme.accentText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(store.isResettingLink || trip.shareToken == nil && store.shareToken == nil)
            .accessibilityHint("The current link stops working")
            .accessibilityIdentifier("share-reset-link")
        }
        .padding(16)
        .liggaCard()
    }

    private func copyLink() {
        guard let shareURL else { return }
        UIPasteboard.general.string = shareURL.absoluteString
        withAnimation(WandererMotion.animation(WandererMotion.snappy, reduceMotion: reduceMotion)) {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.18)) {
                copied = false
            }
        }
    }
}

private enum InviteDelivery: Equatable {
    case sending(String)
    case sent(String)
    case notSent(String)

    var isSending: Bool {
        if case .sending = self { return true }
        return false
    }
}
