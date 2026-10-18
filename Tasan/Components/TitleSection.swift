import SwiftUI

struct TitleSection: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: AppSpacing.xs) {
      Text(title)
        .font(AppTypography.largeTitle)
        .foregroundColor(AppColor.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text(subtitle)
        .font(AppTypography.body)
        .foregroundColor(AppColor.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
  }
}

struct TitleSection_Previews: PreviewProvider {
  static var previews: some View {
    TitleSection(
      title: "Tarkista tapahtuma",
      subtitle: "Tarkista tiedot ennen tallennusta."
    )
    .padding()
    .previewLayout(.sizeThatFits)
  }
}
