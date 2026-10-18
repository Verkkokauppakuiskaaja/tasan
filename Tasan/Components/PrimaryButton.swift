import SwiftUI

struct PrimaryButton: View {
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
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 56)
      .background(AppColor.primary)
      .clipShape(
        RoundedRectangle(
          cornerRadius: AppRadius.button,
          style: .continuous
        )
      )
      .appShadow(AppShadow.medium)
      .opacity(isEnabled ? 1 : 0.5)
    }
    .buttonStyle(.plain)
  }
}

struct PrimaryButton_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: AppSpacing.md) {
      PrimaryButton(title: "Tallenna", systemImage: "checkmark", action: {})
      PrimaryButton(title: "Tallenna", systemImage: "checkmark", action: {})
        .disabled(true)
    }
    .padding()
    .background(AppColor.background)
    .previewLayout(.sizeThatFits)
  }
}
