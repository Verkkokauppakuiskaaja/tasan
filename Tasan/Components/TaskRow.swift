import SwiftUI
import TasanCore

extension Day {
  /// "tänään", "huomenna", "la 24.10.": a near date the way people say it, in the current language.
  func relativeText(today: Day = .today()) -> String {
    let distance = today.days(until: self)
    switch distance {
    case 0: return String(localized: "tänään")
    case 1: return String(localized: "huomenna")
    case -1: return String(localized: "eilen")
    default: return DateText.weekdayDayMonth(self, today: today)
    }
  }
}

extension FamilyTask {
  func timeText(today: Day = .today()) -> String? {
    var parts: [String] = []
    if let prep = prepDay, prep != eventDay {
      parts.append(String(localized: "Valmistelu \(prep.relativeText(today: today))"))
    }
    if let event = eventDay {
      var text = event.relativeText(today: today)
      if let minutes = eventMinutes {
        text += " " + String(localized: "klo \(DateText.time(minutes: minutes))")
      }
      if parts.isEmpty {
        parts.append(text.prefix(1).uppercased() + String(text.dropFirst()))
      } else {
        parts.append(String(localized: "tapahtuma \(text)"))
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  func isLate(today: Day = .today()) -> Bool {
    status == .open && (actionDay.map { $0 < today } ?? false)
  }
}

struct TaskRow: View {
  @Environment(AppModel.self) private var model
  let task: FamilyTask
  var showsResponsible = true

  var body: some View {
    let state = model.state
    let area = state.area(task.areaID)
    let pending = state.pendingTransfer(for: .task(task.id))

    HStack(alignment: .top, spacing: AppSpacing.sm) {
      if showsResponsible {
        MemberAvatar(member: state.member(task.responsibleID), size: 34)
      }
      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(state.displayTitle(of: task))
          .font(AppTypography.bodyMedium)
          .foregroundColor(task.status == .open ? AppColor.textPrimary : AppColor.textSecondary)
          .strikethrough(task.status == .done)
          .multilineTextAlignment(.leading)
        if let time = task.timeText() {
          Text(time)
            .font(AppTypography.caption)
            .foregroundColor(task.isLate() ? AppColor.error : AppColor.textSecondary)
        }
        HStack(spacing: AppSpacing.xxs) {
          if let area {
            Pill(text: area.displayName, systemImage: area.kind.symbolName, color: area.kind.color)
          }
          if let back = task.temporaryReturn {
            Pill(text: String(localized: "Palaa \(state.member(back.memberID)?.name ?? "") \(DateText.dayMonth(back.day))"), systemImage: "arrow.uturn.backward", color: AppColor.detail)
          }
          if pending != nil {
            Pill(text: String(localized: "Siirto odottaa"), systemImage: "hourglass", color: AppColor.detail)
          }
          if task.responsibleID == nil && task.status == .open {
            Pill(text: String(localized: "Avoin"), systemImage: "hand.raised", color: AppColor.success)
          }
        }
      }
      Spacer(minLength: 0)
      if task.source == .image {
        Image(systemName: "camera.viewfinder").foregroundColor(AppColor.textSecondary)
      }
    }
    .padding(.vertical, AppSpacing.xs)
    .contentShape(Rectangle())
  }
}
