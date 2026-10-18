import SwiftUI

struct ActionCard: View {
  @Environment(\.isEnabled) private var isEnabled

  let title: String
  let subtitle: String
  let icon: String
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: AppSpacing.md) {
        ZStack {
          RoundedRectangle(
            cornerRadius: AppRadius.button,
            style: .continuous
          )
          .fill(color.opacity(0.12))
          .frame(width: 54, height: 54)

          Image(systemName: icon)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(color)
        }
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
          Text(title)
            .font(AppTypography.headline)
            .foregroundColor(AppColor.textPrimary)

          Text(subtitle)
            .font(AppTypography.body)
            .foregroundColor(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: AppSpacing.sm)

        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(AppColor.textSecondary)
          .accessibilityHidden(true)
      }
      .padding(AppSpacing.md)
      .background(
        RoundedRectangle(
          cornerRadius: AppRadius.card,
          style: .continuous
        )
        .fill(AppColor.card)
        .appShadow(AppShadow.small)
      )
      .opacity(isEnabled ? 1 : 0.55)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityHint(subtitle)
  }
}

struct ActionCard_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: AppSpacing.md) {
      ActionCard(
        title: String(localized: "Ota kuva"),
        subtitle: String(localized: "Kuvaa tiedote tai kutsu"),
        icon: "camera.fill",
        color: AppColor.primary,
        action: {}
      )

      ActionCard(
        title: String(localized: "Valitse kuva"),
        subtitle: String(localized: "Valitse kuvakaappaus tai kuva"),
        icon: "photo.on.rectangle.angled",
        color: AppColor.detail,
        action: {}
      )
      .disabled(true)
    }
    .padding()
    .background(AppColor.background)
    .previewLayout(.sizeThatFits)
  }
}
