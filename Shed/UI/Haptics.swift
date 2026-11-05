import UIKit

enum Haptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func confirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func reject() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
