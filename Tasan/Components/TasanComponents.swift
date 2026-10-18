import SwiftUI
import TasanCore

/// "Tasan!" in the CalendropAI wordmark style: semibold name, bold accent.
struct Wordmark: View {
  var fontSize: CGFloat = 36
  var textColor: Color = AppColor.textPrimary

  var body: some View {
    (Text("Tasan")
      .fontWeight(.semibold)
      + Text("!")
      .fontWeight(.heavy)
      .foregroundColor(AppColor.detail))
      .font(.system(size: fontSize))
      .foregroundColor(textColor)
      .accessibilityLabel("Tasan")
  }
}

struct Tagline: View {
  var body: some View {
    Text("share the family load")
      .font(AppTypography.bodyMedium)
      .foregroundColor(AppColor.textSecondary)
  }
}

/// A scrolling screen on the app background. Lives inside each tab's NavigationStack.
struct Screen<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      AppColor.background.ignoresSafeArea()
      ScrollView {
        content
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, AppSpacing.lg)
          .padding(.vertical, AppSpacing.md)
      }
      .scrollDismissesKeyboard(.interactively)
    }
  }
}

/// The rounded warm card used for every grouped block.
struct Card<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        .fill(AppColor.card)
        .appShadow(AppShadow.small)
    )
  }
}

struct SectionHeader: View {
  let title: String
  var subtitle: String? = nil
  var count: Int? = nil

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
      Text(title)
        .font(AppTypography.headline)
        .foregroundColor(AppColor.textPrimary)
      if let count, count > 0 {
        Badge(value: count)
      }
      Spacer()
      if let subtitle {
        Text(subtitle)
          .font(AppTypography.caption)
          .foregroundColor(AppColor.textSecondary)
      }
    }
    .padding(.top, AppSpacing.md)
  }
}

struct MemberAvatar: View {
  let member: Member?
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      Circle()
        .fill(member.map { Color(hexString: $0.colorHex) } ?? AppColor.border)
      if let member {
        Text(String(member.name.prefix(1)).uppercased())
          .font(.system(size: size * 0.45, weight: .bold))
          .foregroundColor(.white)
      } else {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: size * 0.42, weight: .semibold))
          .foregroundColor(AppColor.textSecondary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel(member?.name ?? "Avoin")
  }
}

/// A small colored pill, e.g. the area of a task.
struct Pill: View {
  let text: String
  var systemImage: String? = nil
  var color: Color = AppColor.primary

  var body: some View {
    HStack(spacing: AppSpacing.xxs) {
      if let systemImage {
        Image(systemName: systemImage)
      }
      Text(text)
    }
    .font(.caption.weight(.semibold))
    .foregroundColor(color)
    .padding(.horizontal, AppSpacing.xs)
    .padding(.vertical, 4)
    .background(Capsule().fill(color.opacity(0.12)))
  }
}

struct EmptyState: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: AppSpacing.sm) {
      Image(systemName: systemImage)
        .font(.system(size: 28, weight: .semibold))
        .foregroundColor(AppColor.onSecondary)
        .frame(width: 60, height: 60)
        .background(Circle().fill(AppColor.secondary))
      Text(title)
        .font(AppTypography.headline)
        .foregroundColor(AppColor.textPrimary)
      Text(message)
        .font(AppTypography.body)
        .foregroundColor(AppColor.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(AppSpacing.xl)
  }
}

/// Round icon button from CalendropAI's top bar.
struct CircleIconButton: View {
  let systemName: String
  let accessibilityLabel: String
  var badge: Int = 0
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: systemName)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(AppColor.textPrimary)
          .frame(width: 44, height: 44)
          .background(Circle().fill(AppColor.card))
          .appShadow(AppShadow.small)
        Badge(value: badge)
          .offset(x: 6, y: -6)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

extension AreaKind {
  var color: Color {
    switch self {
    case .clothing: return AppColor.primary
    case .school: return AppColor.detail
    case .hobbies: return AppColor.success
    case .parties: return Color(hexString: "9B51E0")
    case .holidays: return Color(hexString: "C99A1C")
    }
  }
}
