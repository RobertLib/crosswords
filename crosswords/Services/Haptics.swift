import UIKit

/// Thin wrapper over UIKit feedback generators that honours the player's setting.
final class Haptics {
    var isEnabled = true

    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        guard isEnabled else { return }
        selection.prepare()
        light.prepare()
        soft.prepare()
        notification.prepare()
    }

    func letter() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }

    func tap() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.6)
    }

    func cellPop() {
        guard isEnabled else { return }
        soft.impactOccurred(intensity: 0.5)
    }

    func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func warning() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    func error() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
    }
}
