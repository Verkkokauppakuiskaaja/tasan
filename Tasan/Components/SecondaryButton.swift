import SwiftUI

struct SecondaryButton: View {
  @Environment(\.isEnabled) private var isEnabled

  let title: String
  let systemImage: String?
  let action: () -> Void

  init(
    title: String,
    systemImage: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.sm) {
        if let systemImage = systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
        }

        Text(title)
          .font(AppTypography.headline)
      }
      .foregroundColor(AppColor.primaryForeground)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 56)
      .background(AppColor.card)
      .overlay(
        RoundedRectangle(
          cornerRadius: AppRadius.button,
          style: .continuous
        )
        .stroke(AppColor.border, lineWidth: 1)
      )
      .clipShape(
        RoundedRectangle(
          cornerRadius: AppRadius.button,
          style: .continuous
        )
      )
      .appShadow(AppShadow.small)
      .opacity(isEnabled ? 1 : 0.5)
    }
    .buttonStyle(.plain)
  }
}

struct SecondaryButton_Previews: PreviewProvider {
  static var previews: some View {
    SecondaryButton(title: String(localized: "Takaisin"), systemImage: "chevron.left", action: {})
      .padding()
      .background(AppColor.background)
      .previewLayout(.sizeThatFits)
  }
}
