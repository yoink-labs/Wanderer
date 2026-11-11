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

    private var webLink: String {
        "https://wanderer.app/trip/\(trip.id.uuidString)"
    }

    private var webURL: URL {
        URL(string: webLink) ?? URL(string: "https://wanderer.app")!
    }

    /// Short, human-readable form of the link. The full URL is what gets
    /// copied and shared.
    private var displayLink: String {
        "wanderer.app/trip/\(trip.id.uuidString.prefix(8).lowercased())…"
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
                TripToolGroupLabel(title: "People", trailing: people.isEmpty ? nil : "\(people.count)")
                peopleCard

                TripToolGroupLabel(title: "Invite by email")
                inviteCard

                TripToolGroupLabel(title: "Link")
                linkCard
            }
            .padding(.horizontal, TripToolsLayout.gutter)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WandererTheme.platinum.ignoresSafeArea())
        .task {
            await store.load(tripID: trip.id)
        }
        .onChange(of: store.errorMessage) { _, message in
            if let message {
                inviteError = message
                store.errorMessage = nil
            }
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
                .textCase(.uppercase)
                .tracking(0.4)
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
                        item: webURL,
                        subject: Text("Join \(trip.title) on Wanderer"),
                        message: Text("I added you to \(trip.title) on Wanderer. Sign in with \(email) to join.")
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

    private func openMail(to email: String) {
        let subject = "Join my trip on Wanderer: \(trip.title)"
        let body = "I added you to \(trip.title) on Wanderer. Sign in with \(email) to join.\n\n\(webLink)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }
        openURL(url)
    }

    // MARK: - Link

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.ligga(.body, weight: .semibold))
                    .foregroundStyle(WandererTheme.muted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anyone with the link can view")
                        .font(.ligga(.subheadline, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                    Text(verbatim: displayLink)
                        .font(.ligga(.footnote))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Trip link")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TripToolSecondaryButton(
                    title: copied ? "Copied" : "Copy link",
                    icon: copied ? "checkmark" : "doc.on.doc"
                ) {
                    copyLink()
                }
                .accessibilityIdentifier("share-copy-link")

                ShareLink(
                    item: webURL,
                    subject: Text(trip.title),
                    message: Text("Follow \(trip.title) on Wanderer.")
                ) {
                    TripToolSecondaryLabel(title: "Share", icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("share-link")
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        }
        .padding(16)
        .liggaCard()
    }

    private func copyLink() {
        UIPasteboard.general.string = webLink
        withAnimation(.easeOut(duration: 0.18)) {
            copied = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
