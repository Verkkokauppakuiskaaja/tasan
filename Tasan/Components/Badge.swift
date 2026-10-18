import SwiftUI

struct Badge: View {
  let value: Int

  var body: some View {
    if value > 0 {
      Text(verbatim: "\(value)")
        .font(.caption2.weight(.bold))
        .foregroundColor(.white)
        .frame(minWidth: 18, minHeight: 18)
        .padding(.horizontal, AppSpacing.xxs)
        .background(AppColor.detail)
        .clipShape(Capsule())
        .accessibilityLabel(Text("\(value) kpl"))
    }
  }
}

struct Badge_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: AppSpacing.md) {
      Badge(value: 1)
      Badge(value: 99)
      Badge(value: 0)
    }
    .padding()
    .previewLayout(.sizeThatFits)
  }
}
