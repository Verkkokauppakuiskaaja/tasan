import SwiftUI

struct AppShadowStyle {
  let color: Color
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat
}

enum AppShadow {
  static let small = AppShadowStyle(
    color: .black.opacity(0.05),
    radius: 6,
    x: 0,
    y: 2
  )

  static let medium = AppShadowStyle(
    color: .black.opacity(0.08),
    radius: 12,
    x: 0,
    y: 6
  )

  static let large = AppShadowStyle(
    color: .black.opacity(0.12),
    radius: 24,
    x: 0,
    y: 12
  )
}

extension View {
  func appShadow(_ style: AppShadowStyle) -> some View {
    shadow(
      color: style.color,
      radius: style.radius,
      x: style.x,
      y: style.y
    )
  }
}
