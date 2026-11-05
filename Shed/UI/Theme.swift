import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum ShedColors {
    static let background = dynamic(light: 0xF7F7F5, dark: 0x000000)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let surfaceVariant = dynamic(light: 0xECECEA, dark: 0x1B1B1B)
    static let text = dynamic(light: 0x171717, dark: 0xF2F2F2)
    static let muted = dynamic(light: 0x666666, dark: 0xA0A0A0)
    static let primary = dynamic(light: 0x171717, dark: 0xF4F4F4)
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let error = dynamic(light: 0xBA1A1A, dark: 0xFF6B68)
    static let outline = dynamic(light: 0xD8D8D4, dark: 0x363636)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
