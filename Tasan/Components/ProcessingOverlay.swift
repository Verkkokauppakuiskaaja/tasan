import SwiftUI

struct ProcessingOverlay: View {
  let message: String

  /*
   * The overlay sits on top of the photo being read. Putting the
   * message straight on the photo let the photo's own text show
   * through behind it, so the two looked overlapped. The photo
   * stays visible but dimmed, and the message sits on a blurred
   * card. The dark color scheme keeps the material dark and the
   * white message readable in both themes.
   */
  var body: some View {
    RoundedRectangle(
      cornerRadius: AppRadius.card,
      style: .continuous
    )
    .fill(Color.black.opacity(0.18))
    .overlay(
      VStack(spacing: AppSpacing.sm) {
        ProgressView()
          .tint(.white)

        Text(message)
          .font(AppTypography.bodyMedium)
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .lineLimit(6)
          .minimumScaleFactor(0.8)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(AppSpacing.lg)
      .frame(maxWidth: 320)
      .background(
        RoundedRectangle(
          cornerRadius: AppRadius.card,
          style: .continuous
        )
        .fill(.regularMaterial)
        .overlay(
          RoundedRectangle(
            cornerRadius: AppRadius.card,
            style: .continuous
          )
          .fill(Color.black.opacity(0.28))
        )
      )
      .padding(AppSpacing.lg)
    )
    .environment(\.colorScheme, .dark)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message)
  }
}

struct ProcessingOverlay_Previews: PreviewProvider {
  static var previews: some View {
    ProcessingOverlay(
      message: String(localized: "Luetaan kuvaa…")
    )
    .frame(width: 300, height: 220)
    .padding()
    .previewLayout(.sizeThatFits)
  }
}
