import SwiftUI
import UIKit

/// Imperative haptics for button actions. Declarative state changes should
/// prefer `.sensoryFeedback(_:trigger:)`; use these where an action closure is
/// the only hook. Keep them light: one tap per primary action, never on drag.
@MainActor
enum LiggaHaptics {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.7)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Press feedback for tappable cards: a slight scale-down that respects
/// Reduce Motion.
struct LiggaPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiggaPressableStyle {
    static var liggaPressable: LiggaPressableStyle { LiggaPressableStyle() }
}
