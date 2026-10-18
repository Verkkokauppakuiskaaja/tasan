import SwiftUI
import UIKit

private extension UIColor {
  convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

private extension Color {
  init(light: UInt32, dark: UInt32) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(
          hex: traits.userInterfaceStyle == .dark
            ? dark
            : light
        )
      }
    )
  }

  init(hex: UInt32) {
    self.init(uiColor: UIColor(hex: hex))
  }
}

enum AppColor {
  static let primary = Color(hex: 0x2560F5)
  static let primaryForeground = Color(light: 0x2560F5, dark: 0x6C93F8)
  static let secondary = Color(hex: 0xF8D374)
  static let detail = Color(hex: 0xEC602F)

  static let background = Color(light: 0xFFFFFF, dark: 0x111111)
  static let card = Color(light: 0xF8F0EC, dark: 0x201B19)

  static let textPrimary = Color(light: 0x111111, dark: 0xF5F1EE)
  static let textSecondary = Color(light: 0x6B645F, dark: 0xA39A94)

  static let onSecondary = Color(hex: 0x111111)
  static let onSecondaryMuted = Color(hex: 0x4A3A05)

  static let success = Color(red: 0.086, green: 0.639, blue: 0.286)
  static let error = Color(red: 0.863, green: 0.149, blue: 0.137)
  static let border = Color(uiColor: .separator).opacity(0.55)
}

extension Color {
  /// Member colors are stored as "RRGGBB" strings so they sync as plain text.
  init(hexString: String) {
    let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    let value = UInt32(cleaned, radix: 16) ?? 0x2560F5
    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}
