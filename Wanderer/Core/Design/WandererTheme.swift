import SwiftUI

enum WandererTheme {
    // Brand palette. These stay fixed: they are the Wanderer identity, used in
    // the mark, gradients and map pins, not as UI surfaces.
    static let charcoal = Color(hex: 0x223843)
    /// Neutral surfaces double as the screen background, so they follow the
    /// system appearance. `charcoal` stays fixed for the mark and map pins.
    static let platinum = Color(light: 0xEFF1F3, dark: 0x0E1417)
    static let dust = Color(light: 0xDBD3D8, dark: 0x2B373D)
    static let desert = Color(hex: 0xD8B4A0)
    static let peach = Color(hex: 0xD77A61)
    static let salmon = Color(hex: 0xDF9581)

    // Semantic colours. Every one of these adapts to the system appearance, so
    // screens never hard-code a light surface.
    static let sand = Color(light: 0xEFF1F3, dark: 0x0E1417)
    static let sandDeep = Color(light: 0xDBD3D8, dark: 0x182126)
    static let card = Color(light: 0xFFFFFF, dark: 0x192328)
    static let cardElevated = Color(light: 0xFFFFFF, dark: 0x202C32)
    static let ink = Color(light: 0x223843, dark: 0xECF1F3)
    static let muted = Color(light: 0x5E6C72, dark: 0x9CACB4)
    static let line = Color(light: 0xDBD3D8, dark: 0x2B373D)
    static let shadow = Color(light: 0x000000, dark: 0x000000)

    static let coral = Color(light: 0xD77A61, dark: 0xE99077)
    static let coralDeep = Color(light: 0xB65E48, dark: 0xF3AA92)
    static let accentText = Color(light: 0xA9533D, dark: 0xF3AA92)
    static let coralSoft = Color(light: 0xF4DCD4, dark: 0x3A2621)
    static let mint = Color(light: 0x4C8C7A, dark: 0x74BFA6)
    static let sky = Color(light: 0x3C5A66, dark: 0x8FB6C4)
    static let plum = Color(light: 0x223843, dark: 0xC9D4D9)

    /// Quiet fill for skeletons, segmented tracks and input wells.
    static let fillMuted = Color(light: 0xE3E6E8, dark: 0x253137)
    /// Primary action fill: charcoal in light, coral in dark so the button does
    /// not disappear into the dark background.
    static let primaryFill = Color(light: 0x223843, dark: 0xD77A61)
    /// Tint for system controls (pickers, segmented controls, form fields).
    static let controlTint = Color(light: 0x223843, dark: 0xE99077)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x1B2428)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x1B2428)

    static let cardRadius: CGFloat = 16
    /// Horizontal gutter shared by every top-level screen.
    static let gutter: CGFloat = 16
    static let screenPadding: CGFloat = gutter

    /// Card radius and shadow soften at accessibility sizes where the card is
    /// mostly text.
    static func cardShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.06)
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
}

extension View {
    /// The one card treatment: surface fill, 16pt continuous radius, a single
    /// soft shadow and no stroke. Follows light and dark automatically.
    func liggaCard() -> some View {
        liggaCard(radius: WandererTheme.cardRadius)
    }

    func liggaCard(radius: CGFloat) -> some View {
        modifier(LiggaCardModifier(radius: radius))
    }

    /// Small uppercase label that sits above a section or hero.
    func liggaOverline() -> some View {
        font(.ligga(.caption, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(WandererTheme.muted)
    }
}

private struct LiggaCardModifier: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(WandererTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: WandererTheme.cardShadow(scheme),
                radius: scheme == .dark ? 0 : 10,
                x: 0,
                y: scheme == .dark ? 0 : 4
            )
    }
}
