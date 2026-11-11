import AuthenticationServices
import MapKit
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("wanderer.selectedLanguage") private var storedLanguage = "en"
    @AppStorage("wanderer.isGuest") private var isGuest = false

    @State private var showLanguageSheet = false
    @State private var showEmailAuth = false
    @State private var emailAuthSignUp = false

    private var language: LanguageOption {
        LanguageOption.named(storedLanguage)
    }

    private var isBusy: Bool { auth.isWorking }

    @Environment(\.colorScheme) private var colorScheme

    private func startApple() {
        guard !isBusy else { return }
        LiggaHaptics.tap()
        Task { await auth.signInWithApple() }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero(
                        topInset: proxy.safeAreaInsets.top,
                        minHeight: max(300, proxy.size.height * 0.56) + proxy.safeAreaInsets.top
                    )

                    authSheet
                        .padding(.top, -LiggaSpace.l)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
        }
        .background {
            // Charcoal behind the hero's overscroll, white behind the sheet.
            VStack(spacing: 0) {
                WandererTheme.charcoal
                WandererTheme.card
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSheet(selectedID: $storedLanguage)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthSheet(startInSignUp: emailAuthSignUp)
                .environmentObject(auth)
        }
    }

    // MARK: - Hero

    private func hero(topInset: CGFloat, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: LiggaSpace.xs) {
            Text("Plan trips on a map,\nday by day.")
                .font(.display(.title))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Build an itinerary, pin every stop and keep bookings and notes in one place.")
                .font(.ligga(.body))
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WandererTheme.gutter)
        // Clears the top bar above, and the sheet, which overlaps by 24pt.
        .padding(.top, topInset + 44 + LiggaSpace.xl)
        .padding(.bottom, LiggaSpace.l + LiggaSpace.l)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottomLeading)
        .overlay(alignment: .top) {
            topBar
                .padding(.horizontal, WandererTheme.gutter)
                .padding(.top, topInset + LiggaSpace.xs)
        }
        .background {
            ZStack {
                SignInMapHero()
                LinearGradient(
                    stops: [
                        .init(color: WandererTheme.charcoal.opacity(0.55), location: 0),
                        .init(color: WandererTheme.charcoal.opacity(0), location: 0.28),
                        .init(color: WandererTheme.charcoal.opacity(0), location: 0.4),
                        .init(color: WandererTheme.charcoal.opacity(0.94), location: 0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
        }
        .clipped()
    }

    private var topBar: some View {
        HStack {
            Button {
                LiggaHaptics.tap()
                showLanguageSheet = true
            } label: {
                HStack(spacing: LiggaSpace.xs) {
                    Image(systemName: "globe")
                        .accessibilityHidden(true)
                    Text(language.nativeName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.ligga(.caption, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(.ligga(.subheadline, weight: .semibold))
                .foregroundStyle(WandererTheme.ink)
                .padding(.horizontal, LiggaSpace.m)
                .frame(minHeight: 40)
                .background(WandererTheme.card, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.liggaPressable)
            .accessibilityLabel("Language, \(language.englishName)")
            .accessibilityHint("Changes the app language")
            .accessibilityIdentifier("auth-language")

            Spacer()

            WandererMark(size: 36)
        }
    }

    // MARK: - Auth sheet

    private var authSheet: some View {
        VStack(spacing: LiggaSpace.s) {
            // Apple first and at full prominence (App Review 4.8, HIG): the
            // system button, black on light and white on dark.
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { _ in
                // Clerk runs its own authorization; this button only starts it.
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            // The system button keeps its first style; rebuild it on change.
            .id(colorScheme)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous))
            .overlay {
                // Intercept the tap so Clerk drives the ASAuthorization request.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { startApple() }
                    .accessibilityHidden(true)
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.6 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Continue with Apple")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { startApple() }
            .accessibilityIdentifier("auth-apple")

            Button {
                LiggaHaptics.tap()
                Task { await auth.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleMark()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(colorScheme == .dark ? Color.white : Color(hex: 0x1F1F1F))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    colorScheme == .dark ? Color(hex: 0x131314) : Color.white,
                    in: RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color(hex: 0x8E918F) : Color(hex: 0x747775), lineWidth: 1)
                )
            }
            .buttonStyle(.liggaPressable)
            .disabled(isBusy)
            .accessibilityIdentifier("auth-google")

            if let message = auth.errorMessage, !showEmailAuth {
                Text(message)
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.signal)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("auth-social-error")
            }

            HStack(spacing: LiggaSpace.s) {
                Rectangle().fill(WandererTheme.line).frame(height: 1)
                Text("or")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
                Rectangle().fill(WandererTheme.line).frame(height: 1)
            }
            .accessibilityHidden(true)

            Button {
                LiggaHaptics.tap()
                emailAuthSignUp = false
                showEmailAuth = true
            } label: {
                Label("Continue with email", systemImage: "envelope")
                    .font(.ligga(.headline, weight: .semibold))
                    .foregroundStyle(WandererTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: WandererTheme.controlRadius, style: .continuous)
                            .strokeBorder(WandererTheme.line, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.liggaPressable)
            .disabled(isBusy)
            .accessibilityHint("We'll email you a six-digit code")
            .accessibilityIdentifier("auth-email")

            Button {
                LiggaHaptics.tap()
                emailAuthSignUp = true
                showEmailAuth = true
            } label: {
                Text("New to Wanderer? \(Text("Create an account").foregroundStyle(WandererTheme.accentText).fontWeight(.semibold))")
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("auth-sign-up")

            Divider()
                .overlay(WandererTheme.line.opacity(0.6))

            VStack(spacing: LiggaSpace.xxs) {
                Button {
                    LiggaHaptics.tap()
                    isGuest = true
                } label: {
                    Text("Explore as a guest")
                        .font(.ligga(.body, weight: .semibold))
                        .foregroundStyle(WandererTheme.ink)
                        .padding(.horizontal, LiggaSpace.m)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("auth-guest")

                Text("You can create an account any time.")
                    .font(.ligga(.footnote))
                    .foregroundStyle(WandererTheme.muted)
            }
        }
        .padding(.horizontal, WandererTheme.gutter)
        .padding(.top, LiggaSpace.l)
        .padding(.bottom, LiggaSpace.l)
        .frame(maxWidth: .infinity)
        .background(
            WandererTheme.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
    }
}

/// A real, non-interactive MapKit view of a sample Rio day: the product's own
/// map-and-numbered-stops idea instead of an illustration.
private struct SignInMapHero: View {
    private struct Stop: Identifiable {
        let id: Int
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private static let stops: [Stop] = [
        Stop(id: 1, name: "Christ the Redeemer", coordinate: CLLocationCoordinate2D(latitude: -22.9519, longitude: -43.2105)),
        Stop(id: 2, name: "Selarón Steps", coordinate: CLLocationCoordinate2D(latitude: -22.9154, longitude: -43.1791)),
        Stop(id: 3, name: "Sugarloaf Mountain", coordinate: CLLocationCoordinate2D(latitude: -22.9492, longitude: -43.1546)),
        Stop(id: 4, name: "Copacabana", coordinate: CLLocationCoordinate2D(latitude: -22.9711, longitude: -43.1822))
    ]

    // Centred south of the route so the pins sit in the clear upper half,
    // above the headline.
    private static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -22.968, longitude: -43.183),
        span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
    )

    var body: some View {
        Map(initialPosition: .region(Self.region), interactionModes: []) {
            MapPolyline(coordinates: Self.stops.map(\.coordinate))
                .stroke(
                    WandererTheme.peach,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )

            ForEach(Self.stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    pin(number: stop.id)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pin(number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: 0x10283A))
            .frame(width: 30, height: 30)
            .background(Color(hex: 0xF2A922), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

private struct LanguageSheet: View {
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(LanguageOption.all) { language in
                        Button {
                            LiggaHaptics.selection()
                            selectedID = language.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.nativeName)
                                        .font(.ligga(.body, weight: .medium))
                                        .foregroundStyle(WandererTheme.ink)
                                    if language.englishName != language.nativeName {
                                        Text(language.englishName)
                                            .font(.ligga(.caption))
                                            .foregroundStyle(WandererTheme.muted)
                                    }
                                }
                                Spacer()
                                if language.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(WandererTheme.coral)
                                }
                            }
                            .padding(.horizontal, LiggaSpace.m)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(language.id == selectedID ? WandererTheme.coralSoft.opacity(0.7) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(language.id == selectedID ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, LiggaSpace.s)
                .padding(.vertical, LiggaSpace.xs)
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthStore())
}

/// Google's four-colour "G", drawn as arcs so no raster asset is bundled.
/// Angles run clockwise from three o'clock; the gap sits top-right.
private struct GoogleMark: View {
    private static let segments: [(Double, Double, UInt32)] = [
        (0, 45, 0x4285F4),    // blue, lower right
        (45, 135, 0x34A853),  // green, bottom
        (135, 200, 0xFBBC05), // yellow, lower left
        (200, 315, 0xEA4335)  // red, top
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let line = size * 0.2
            ZStack {
                ForEach(0..<Self.segments.count, id: \.self) { index in
                    let segment = Self.segments[index]
                    Circle()
                        .trim(from: segment.0 / 360, to: segment.1 / 360)
                        .stroke(Color(hex: segment.2), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                        .padding(line / 2)
                }
                Rectangle()
                    .fill(Color(hex: 0x4285F4))
                    .frame(width: size * 0.5 - line / 2, height: line)
                    .offset(x: size * 0.25 - line / 4)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
