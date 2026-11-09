import SwiftUI

enum WandererTheme {
    // Brand palette
    static let charcoal = Color(hex: 0x223843)
    static let platinum = Color(hex: 0xEFF1F3)
    static let dust = Color(hex: 0xDBD3D8)
    static let desert = Color(hex: 0xD8B4A0)
    static let peach = Color(hex: 0xD77A61)
    static let salmon = Color(hex: 0xDF9581)

    // Semantic aliases used across the app
    static let sand = platinum
    static let sandDeep = dust
    static let card = Color.white
    static let ink = charcoal
    static let muted = Color(hex: 0x5E6C72)
    static let coral = peach
    static let coralDeep = Color(hex: 0xB65E48)
    static let accentText = Color(hex: 0xA9533D)
    static let coralSoft = Color(hex: 0xF4DCD4)
    static let mint = Color(hex: 0x4C8C7A)
    static let sky = Color(hex: 0x3C5A66)
    static let plum = charcoal
    static let line = dust
    static let shadow = Color.black.opacity(0.08)

    /// Quiet fill for skeletons, segmented tracks and input wells.
    static let fillMuted = dust.opacity(0.45)
    /// The single card shadow. Cards never also carry a stroke.
    static let cardShadow = Color.black.opacity(0.06)

    static let cardRadius: CGFloat = 16
    /// Horizontal gutter shared by every top-level screen.
    static let gutter: CGFloat = 16
    static let screenPadding: CGFloat = gutter
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
    /// The one card treatment: white fill, 16pt continuous radius, a single
    /// soft shadow and no stroke.
    func liggaCard() -> some View {
        liggaCard(radius: WandererTheme.cardRadius)
    }

    func liggaCard(radius: CGFloat) -> some View {
        background(WandererTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: WandererTheme.cardShadow, radius: 10, x: 0, y: 4)
    }

    /// Small uppercase label that sits above a section or hero.
    func liggaOverline() -> some View {
        font(.ligga(.caption, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(WandererTheme.muted)
    }
}
