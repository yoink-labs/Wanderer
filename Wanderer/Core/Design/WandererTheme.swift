import SwiftUI

/// "Atlas": cool map paper, deep-sea ink and a marigold route line. The route
/// colour is the one loud thing in the app; everything else stays quiet so the
/// itinerary line and map pins carry the identity.
enum WandererTheme {
    // MARK: Atlas palette (fixed identity colours)

    /// Deep-sea ink. Fixed: used for the mark, map pins and photo scrims.
    static let charcoal = Color(hex: 0x10283A)
    /// Marigold route. Fixed hue for pins and the itinerary line.
    static let route = Color(light: 0xF2A922, dark: 0xFFC14D)
    static let routeSoft = Color(light: 0xFCEBC8, dark: 0x3A2E14)
    static let sea = Color(light: 0x2C6E8F, dark: 0x7FC0DF)
    static let lagoon = Color(light: 0x1E8A6E, dark: 0x5FD0AE)
    static let signal = Color(light: 0xC8402F, dark: 0xFF8A78)

    // MARK: Surfaces (follow the system appearance)

    static let platinum = Color(light: 0xEEF2F3, dark: 0x070D12)
    static let dust = Color(light: 0xD3DBD8, dark: 0x22323C)
    static let sand = platinum
    static let sandDeep = Color(light: 0xDDE4E3, dark: 0x0F1A22)
    static let card = Color(light: 0xFFFFFF, dark: 0x101B23)
    static let cardElevated = Color(light: 0xFFFFFF, dark: 0x16242E)
    static let ink = Color(light: 0x10283A, dark: 0xE8EEF1)
    static let muted = Color(light: 0x56697A, dark: 0x93A6B3)
    static let line = Color(light: 0xD3DBD8, dark: 0x24343F)
    static let shadow = Color.black

    /// Chrome that floats over the map. Materials do the blur; this stroke
    /// and shadow keep the card's edge legible on a busy map.
    static let glassStroke = Color(light: 0xFFFFFF, dark: 0xFFFFFF).opacity(0.55)
    static let glassEdge = Color(light: 0x10283A, dark: 0x000000).opacity(0.10)
    static let glassTint = Color(light: 0xFFFFFF, dark: 0x0B151C)

    // MARK: Semantic aliases kept for existing screens

    /// Accent fill (chips, pins, highlights).
    static let coral = route
    /// Accent used for icons and text on light surfaces; dark enough to read.
    static let coralDeep = Color(light: 0x8A5300, dark: 0xFFC966)
    static let accentText = coralDeep
    static let coralSoft = routeSoft
    static let peach = route
    static let salmon = Color(light: 0xF6C566, dark: 0xFFD27F)
    static let desert = Color(light: 0xE7D3A8, dark: 0x5A4A27)
    static let mint = lagoon
    static let sky = sea
    static let plum = ink

    /// Quiet fill for skeletons, segmented tracks and input wells.
    static let fillMuted = Color(light: 0xE2E8E8, dark: 0x1D2D38)
    /// Primary action: ink on paper in light, marigold in dark.
    static let primaryFill = Color(light: 0x10283A, dark: 0xFFC14D)
    static let controlTint = Color(light: 0x10283A, dark: 0xFFC14D)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x0B151C)
    static let onAccent = Color(hex: 0x10283A)

    /// Radii by hierarchy, not one radius everywhere: photo postcards are the
    /// roundest, grouped lists sit in between, controls are tighter.
    static let postcardRadius: CGFloat = 26
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
    /// Horizontal gutter shared by every top-level screen.
    static let gutter: CGFloat = 20
    static let screenPadding: CGFloat = gutter
    static let minimumTarget: CGFloat = 44
    static let buttonHeight: CGFloat = 52

    static func cardShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.clear : Color(hex: 0x10283A, opacity: 0.07)
    }
}

/// Spring presets. Every call site goes through `WandererMotion.animation` so
/// Reduce Motion collapses them to a short cross-fade.
enum WandererMotion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.86)

    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : base
    }
}

/// User-selectable appearance, defaulting to the system setting.
enum WandererAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 4pt spacing grid. Prefer these over literal values in new layout code.
enum LiggaSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// A colour that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

extension Font {
    /// Wanderer uses SF Pro for an editorial, travel-magazine feel. Rounded
    /// numerals stay available through `.system(..., design: .rounded)` in
    /// small badges where the extra warmth helps.
    static func ligga(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default).weight(weight)
    }

    static func wanderer(_ role: WandererType) -> Font {
        .system(role.textStyle, design: .default).weight(role.weight)
    }
}

/// A single hierarchy for titles. Native text styles retain optical sizing and
/// Dynamic Type metrics, including all accessibility sizes.
enum WandererType {
    case screen, hero, title, section, card, group

    var textStyle: Font.TextStyle {
        switch self {
        case .screen: return .largeTitle
        case .hero: return .title
        case .title: return .title2
        case .section: return .title3
        case .card: return .headline
        case .group: return .subheadline
        }
    }

    var weight: Font.Weight { self == .screen ? .bold : .semibold }
    var tracking: CGFloat {
        switch self {
        case .screen: return -0.4
        case .hero: return -0.2
        default: return 0
        }
    }
}

private struct WandererHeadingModifier: ViewModifier {
    let role: WandererType
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var leading: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .font(.wanderer(role))
            .tracking(dynamicTypeSize.isAccessibilitySize ? 0 : role.tracking)
            .lineSpacing(leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Structural titles only. Values and controls use `Font.wanderer` without
    /// header traits. Color stays with the surface (ink on cards, white on photos).
    func wandererHeading(_ role: WandererType) -> some View {
        modifier(WandererHeadingModifier(role: role))
    }
}

/// Page background: map paper, warmed by a sea and marigold glow. Subtle in
/// light, richer in dark where the glow carries the identity.
struct WandererBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WandererTheme.platinum
            RadialGradient(
                colors: [WandererTheme.sea.opacity(scheme == .dark ? 0.12 : 0.05), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 620
            )
            RadialGradient(
                colors: [WandererTheme.route.opacity(scheme == .dark ? 0.06 : 0.04), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// The one card treatment: surface fill, shared continuous radius, a single
    /// soft shadow and no stroke. Follows light and dark automatically.
    func liggaCard() -> some View {
        liggaCard(radius: WandererTheme.cardRadius)
    }
    func liggaCard(radius: CGFloat) -> some View {
        modifier(LiggaCardModifier(radius: radius))
    }

    /// Floating chrome over the map: a system material, a hairline highlight
    /// and a deep shadow. Used by the planner panel and floating controls so
    /// the map stays visible (and alive) underneath.
    func wandererGlass(radius: CGFloat = 28, tintOpacity: Double = 0.10) -> some View {
        modifier(WandererGlassModifier(radius: radius, tintOpacity: tintOpacity))
    }

    /// Small sentence-case label that sits above a section or hero.
    func liggaOverline() -> some View {
        font(.ligga(.footnote, weight: .semibold))
            .foregroundStyle(WandererTheme.muted)
    }
}

private struct WandererGlassModifier: ViewModifier {
    let radius: CGFloat
    let tintOpacity: Double
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape
                    .fill(.thickMaterial)
                    .overlay {
                        shape.fill(WandererTheme.glassTint.opacity(scheme == .dark ? tintOpacity : 0.10))
                    }
            }
            .overlay {
                shape.strokeBorder(WandererTheme.glassStroke.opacity(scheme == .dark ? 0.16 : 0.6), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 30, x: 0, y: 14)
    }
}

private struct LiggaCardModifier: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                // Dark mode drops the shadow; a hairline keeps cards separate.
                if scheme == .dark {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(WandererTheme.line, lineWidth: 1)
                }
            }
            .shadow(
                color: WandererTheme.cardShadow(scheme),
                radius: scheme == .dark ? 0 : 14,
                x: 0,
                y: scheme == .dark ? 0 : 6
            )
    }
}
