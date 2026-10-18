import SwiftUI
import TasanCore

extension Day {
  /// "tänään", "huomenna", "la 24.10." — how a Finn reads a near date.
  func relativeText(today: Day = .today()) -> String {
    let distance = today.days(until: self)
    switch distance {
    case 0: return "tänään"
    case 1: return "huomenna"
    case -1: return "eilen"
    default:
      let weekday = FinnishCalendar.weekdayShortNames[isoWeekday() - 1]
      return year == today.year ? "\(weekday) \(finnishShortString)" : "\(weekday) \(finnishString)"
    }
  }
}

extension FamilyTask {
  func timeText(today: Day = .today()) -> String? {
    var parts: [String] = []
    if let prep = prepDay, prep != eventDay {
      parts.append("Valmistelu \(prep.relativeText(today: today))")
    }
    if let event = eventDay {
      var text = event.relativeText(today: today)
      if let minutes = eventMinutes {
        text += String(format: " klo %d.%02d", minutes / 60, minutes % 60)
      }
      if parts.isEmpty {
        parts.append(text.prefix(1).uppercased() + String(text.dropFirst()))
      } else {
        parts.append("tapahtuma \(text)")
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
        Text(task.title)
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
            Pill(text: area.name, systemImage: area.kind.symbolName, color: area.kind.color)
          }
          if let back = task.temporaryReturn {
            Pill(text: "Palaa \(state.member(back.memberID)?.name ?? "") \(back.day.finnishShortString)", systemImage: "arrow.uturn.backward", color: AppColor.detail)
          }
          if pending != nil {
            Pill(text: "Siirto odottaa", systemImage: "hourglass", color: AppColor.detail)
          }
          if task.responsibleID == nil && task.status == .open {
            Pill(text: "Avoin", systemImage: "hand.raised", color: AppColor.success)
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
