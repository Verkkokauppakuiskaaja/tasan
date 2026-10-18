import SwiftUI
import TasanCore

/*
 * The family calendar inside the app: everyone's events in one
 * view. Tasks and their preparation days come from the family
 * data; each adult's own calendar events come from their phone
 * (this phone reads its own, the other adult's arrive as shared
 * busy blocks).
 */
struct FamilyCalendarView: View {
  @Environment(AppModel.self) private var model
  @State private var hiddenMembers: Set<UUID> = []
  @State private var weekOffset = 0

  private struct Item: Identifiable {
    enum Kind { case event, prep, external }
    var id: String
    var kind: Kind
    var title: String
    var time: String?
    var memberID: UUID?
    var taskID: UUID?
    /// Minutes after midnight for ordering; all-day items first.
    var order: Int = -1
  }

  var body: some View {
    let state = model.state
    let start = Day.today().adding(days: -(Day.today().isoWeekday() - 1) + weekOffset * 7)
    let days = (0..<14).map { start.adding(days: $0) }

    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          HStack {
            TitleSection(title: "Perheen kalenteri", subtitle: "Viikot \(start.isoWeek())–\(start.adding(days: 7).isoWeek())")
          }
          HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
            Spacer()
            Button("Tämä viikko") { weekOffset = 0 }.disabled(weekOffset == 0)
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
          }
          .font(AppTypography.headline)

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
              ForEach(state.adults) { member in
                Button {
                  if hiddenMembers.contains(member.id) { hiddenMembers.remove(member.id) } else { hiddenMembers.insert(member.id) }
                } label: {
                  HStack(spacing: 6) {
                    MemberAvatar(member: member, size: 22)
                    Text(member.name).font(AppTypography.caption.weight(.semibold))
                  }
                  .padding(.horizontal, AppSpacing.sm)
                  .padding(.vertical, 6)
                  .background(Capsule().fill(AppColor.card))
                  .opacity(hiddenMembers.contains(member.id) ? 0.4 : 1)
                }
                .buttonStyle(.plain)
              }
            }
          }

          if !model.calendars.appleEnabled && !model.calendars.googleEnabled {
            Card {
              Text("Yhdistä oma kalenterisi asetuksista, niin näet omat menosi tässä ja tehtäväsi kalenterissasi.")
                .font(AppTypography.body)
                .foregroundColor(AppColor.textSecondary)
            }
          }

          ForEach(days, id: \.self) { day in
            let dayItems = items(on: day, state: state)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
              HStack {
                Text("\(FinnishCalendar.weekdayNames[day.isoWeekday() - 1].capitalized) \(day.finnishShortString)")
                  .font(AppTypography.headline)
                  .foregroundColor(day == Day.today() ? AppColor.primaryForeground : AppColor.textPrimary)
                if day == Day.today() { Pill(text: "Tänään") }
              }
              if dayItems.isEmpty {
                Text("–").foregroundColor(AppColor.textSecondary)
              }
              ForEach(dayItems) { item in
                itemRow(item, state: state)
              }
            }
            .padding(.vertical, AppSpacing.xxs)
            Divider()
          }
        }
      }
      .navigationDestination(for: UUID.self) { TaskDetailView(taskID: $0) }
      .refreshable { await model.refreshMyEvents() }
      .task { await model.refreshMyEvents() }
    }
  }

  @ViewBuilder
  private func itemRow(_ item: Item, state: FamilyState) -> some View {
    let member = state.member(item.memberID)
    let color = member.map { Color(hexString: $0.colorHex) } ?? AppColor.success
    let row = HStack(spacing: AppSpacing.sm) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 4, height: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .font(item.kind == .external ? AppTypography.body : AppTypography.bodyMedium)
          .foregroundColor(item.kind == .external ? AppColor.textSecondary : AppColor.textPrimary)
        HStack(spacing: 6) {
          if let time = item.time { Text(time) }
          Text(member?.name ?? "Avoin")
          if item.kind == .prep { Text("· valmistelu") }
        }
        .font(AppTypography.caption)
        .foregroundColor(AppColor.textSecondary)
      }
      Spacer()
      if item.kind != .external {
        Image(systemName: item.kind == .prep ? "hammer" : "checklist").foregroundColor(color)
      }
    }
    if let taskID = item.taskID {
      NavigationLink(value: taskID) { row }.buttonStyle(.plain)
    } else {
      row
    }
  }

  private func items(on day: Day, state: FamilyState) -> [Item] {
    var result: [Item] = []
    for task in state.tasks where task.status == .open {
      if let member = task.responsibleID, hiddenMembers.contains(member) { continue }
      if task.eventDay == day {
        let time = task.eventMinutes.map { String(format: "%d.%02d", $0 / 60, $0 % 60) }
        result.append(Item(id: "\(task.id)|e", kind: .event, title: task.title, time: time, memberID: task.responsibleID, taskID: task.id, order: task.eventMinutes ?? -1))
      }
      if let prep = task.prepDay, prep == day, prep != task.eventDay {
        result.append(Item(id: "\(task.id)|p", kind: .prep, title: task.title, time: nil, memberID: task.responsibleID, taskID: task.id))
      }
    }

    let dayStart = day.date()
    let dayEnd = day.adding(days: 1).date()
    let minutes: (Date) -> Int = { date in
      let parts = Calendar.finnish.dateComponents([.hour, .minute], from: date)
      return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    let formatter: (Date) -> String = { date in
      let parts = Calendar.finnish.dateComponents([.hour, .minute], from: date)
      return String(format: "%d.%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    if let meID = model.meID, !hiddenMembers.contains(meID) {
      for event in model.myEvents where event.start < dayEnd && event.end > dayStart {
        result.append(Item(id: event.id, kind: .external, title: event.title, time: event.isAllDay ? nil : formatter(event.start), memberID: meID, taskID: nil, order: event.isAllDay ? -1 : minutes(event.start)))
      }
    }
    for busy in state.busy where busy.id != model.meID && !hiddenMembers.contains(busy.id) {
      for (index, block) in busy.blocks.enumerated() where block.start < dayEnd && block.end > dayStart {
        result.append(
          Item(
            id: "\(busy.id)|\(index)",
            kind: .external,
            title: block.title ?? "Varattu",
            time: block.isAllDay ? nil : "\(formatter(block.start))–\(formatter(block.end))",
            memberID: busy.id,
            taskID: nil,
            order: block.isAllDay ? -1 : minutes(block.start)
          )
        )
      }
    }
    return result.sorted { $0.order < $1.order }
  }
}
