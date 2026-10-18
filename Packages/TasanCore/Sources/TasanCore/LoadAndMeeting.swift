import Foundation

// MARK: - Load ("Jakonäkymä")

/*
 * How the load is split right now. Not points: just how many open
 * responsibilities each adult carries, per area, so the family can
 * see the split and even it out together.
 */
public struct LoadSummary: Equatable, Sendable {
  public struct Row: Equatable, Sendable, Identifiable {
    public var memberID: UUID?
    public var openTasks: Int
    public var upcomingTasks: Int
    public var ownedAreas: [UUID]
    public var tasksByArea: [UUID: Int]
    public var completedInPeriod: Int
    public var id: String { memberID?.uuidString ?? "open" }
  }

  public var rows: [Row]
  public var openForTaking: Int

  public static func make(from state: FamilyState, today: Day, upcomingDays: Int = 14, periodDays: Int = 30, now: Date = Date()) -> LoadSummary {
    let open = state.tasks.filter { $0.status == .open }
    let soon = today.adding(days: upcomingDays)
    let periodStart = now.addingTimeInterval(-Double(periodDays) * 86_400)

    let rows = state.responsibleCandidates.map { member -> Row in
      let mine = open.filter { $0.responsibleID == member.id }
      var byArea: [UUID: Int] = [:]
      for task in mine {
        if let areaID = task.areaID { byArea[areaID, default: 0] += 1 }
      }
      return Row(
        memberID: member.id,
        openTasks: mine.count,
        upcomingTasks: mine.filter { ($0.actionDay ?? today) <= soon }.count,
        ownedAreas: state.areas.filter { $0.enabled && $0.ownerID == member.id }.map(\.id),
        tasksByArea: byArea,
        completedInPeriod: state.tasks.filter {
          $0.status == .done && $0.completedByID == member.id && ($0.completedAt ?? .distantPast) >= periodStart
        }.count
      )
    }
    return LoadSummary(rows: rows, openForTaking: open.filter { $0.responsibleID == nil }.count)
  }

  /// Share of open tasks for a member, 0...1. Equal split is 1 / adults.
  public func share(of memberID: UUID) -> Double {
    let total = rows.reduce(0) { $0 + $1.openTasks }
    guard total > 0, let row = rows.first(where: { $0.memberID == memberID }) else { return 0 }
    return Double(row.openTasks) / Double(total)
  }
}

// MARK: - Overlaps

/// A busy block read from someone's own calendar.
public struct BusyInterval: Equatable, Sendable {
  public var memberID: UUID
  public var start: Date
  public var end: Date
  public var title: String?

  public init(memberID: UUID, start: Date, end: Date, title: String? = nil) {
    self.memberID = memberID
    self.start = start
    self.end = end
    self.title = title
  }
}

public struct Overlap: Equatable, Sendable, Identifiable {
  public var taskID: UUID
  public var memberID: UUID
  public var conflictingTitle: String?
  /// Another adult who looks free at that time, as a transfer suggestion.
  public var suggestedMemberID: UUID?
  public var id: UUID { taskID }
}

public enum OverlapDetector {
  /*
   * A timed task overlaps when its responsible person has
   * something else in their calendar at the same time. All-day
   * tasks never overlap: buying a present fits around a work day.
   */
  public static func overlaps(in state: FamilyState, busy: [BusyInterval], calendar: Calendar = .finnish) -> [Overlap] {
    state.tasks.compactMap { task -> Overlap? in
      guard task.status == .open, let responsible = task.responsibleID,
        let day = task.eventDay, let minutes = task.eventMinutes
      else { return nil }
      let start = day.date(minutes: minutes, calendar: calendar)
      let end = start.addingTimeInterval(Double(task.eventDurationMinutes ?? 60) * 60)
      func clash(_ memberID: UUID) -> BusyInterval? {
        busy.first { $0.memberID == memberID && $0.start < end && $0.end > start }
      }
      guard let conflict = clash(responsible) else { return nil }
      let alternative = state.responsibleCandidates.first { $0.id != responsible && clash($0.id) == nil }
      return Overlap(taskID: task.id, memberID: responsible, conflictingTitle: conflict.title, suggestedMemberID: alternative?.id)
    }
  }
}

// MARK: - Family meeting ("Perhepalaveri")

/*
 * The meeting screen is prepared by the app: what is coming,
 * who carries what, what nobody has taken yet. The weekly one
 * looks 7 days ahead, the monthly one 4-6 weeks plus the year
 * clock items that are coming but not yet created.
 */
public struct MeetingAgenda: Equatable, Sendable {
  public var kind: MeetingKind
  public var from: Day
  public var to: Day
  /// Tasks whose event or preparation falls in the window.
  public var upcoming: [FamilyTask]
  public var openForTaking: [FamilyTask]
  public var overdue: [FamilyTask]
  public var pendingTransfers: [TransferRequest]
  public var overlaps: [Overlap]
  /// Year clock occurrences in the window that have no task yet (monthly only).
  public var comingFromYearClock: [YearClock.Occurrence]
  public var birthdays: [Birthday]
  public var load: LoadSummary
  /// What was agreed last time, to look back on.
  public var previous: MeetingRecord?

  public static func == (lhs: MeetingAgenda, rhs: MeetingAgenda) -> Bool {
    lhs.kind == rhs.kind && lhs.from == rhs.from && lhs.to == rhs.to && lhs.upcoming == rhs.upcoming
      && lhs.openForTaking == rhs.openForTaking && lhs.overdue == rhs.overdue
  }

  public static func make(
    _ kind: MeetingKind,
    state: FamilyState,
    today: Day,
    busy: [BusyInterval] = [],
    now: Date = Date()
  ) -> MeetingAgenda {
    let days = kind == .weekly ? 7 : 42
    let to = today.adding(days: days)
    let open = state.tasks.filter { $0.status == .open }

    func inWindow(_ task: FamilyTask) -> Bool {
      let dates = [task.eventDay, task.prepDay].compactMap { $0 }
      return dates.contains { $0 >= today && $0 <= to }
    }

    let upcoming = open.filter(inWindow).sorted { ($0.actionDay ?? to) < ($1.actionDay ?? to) }
    let existingKeys = Set(state.tasks.compactMap(\.occurrenceKey))
    let coming = kind == .monthly
      ? YearClock().occurrences(in: state, from: today, to: to).filter { !existingKeys.contains($0.key) }
      : []

    let birthdays: [Birthday] = state.members.compactMap { member in
      guard let birthday = member.birthday else { return nil }
      for year in [today.year, today.year + 1] {
        let day = Day(year, birthday.month, min(birthday.day, Day.daysInMonth(birthday.month, year: year)))
        if day >= today && day <= to { return Birthday(memberID: member.id, day: day) }
      }
      return nil
    }

    return MeetingAgenda(
      kind: kind,
      from: today,
      to: to,
      upcoming: upcoming,
      openForTaking: open.filter { $0.responsibleID == nil }.sorted { ($0.actionDay ?? to) < ($1.actionDay ?? to) },
      overdue: open.filter { ($0.eventDay ?? $0.prepDay ?? today) < today },
      pendingTransfers: state.transfers.filter { $0.status == .pending },
      overlaps: OverlapDetector.overlaps(in: state, busy: busy).filter { overlap in upcoming.contains { $0.id == overlap.taskID } },
      comingFromYearClock: coming,
      birthdays: birthdays,
      load: LoadSummary.make(from: state, today: today, upcomingDays: days, periodDays: kind == .weekly ? 7 : 30, now: now),
      previous: state.meetings.filter { $0.kind == kind }.max { $0.date < $1.date }
    )
  }

  public struct Birthday: Equatable, Sendable, Identifiable {
    public var memberID: UUID
    public var day: Day
    public var id: UUID { memberID }
  }

  public struct ResponsibleGroup: Equatable, Sendable, Identifiable {
    public var memberID: UUID?
    public var tasks: [FamilyTask]
    public var id: String { memberID?.uuidString ?? "open" }
  }

  /// Tasks grouped by responsible person, for "Kenellä on tällä viikolla mitäkin". Adults first, open tasks last.
  public func upcomingByResponsible(order: [UUID] = []) -> [ResponsibleGroup] {
    let grouped = Dictionary(grouping: upcoming, by: \.responsibleID)
    func rank(_ id: UUID?) -> Int { id.flatMap { order.firstIndex(of: $0) } ?? (id == nil ? Int.max : Int.max - 1) }
    return grouped.map { ResponsibleGroup(memberID: $0.key, tasks: $0.value) }.sorted { rank($0.memberID) < rank($1.memberID) }
  }
}

// MARK: - Meeting change log

/*
 * Collects what was changed during a meeting, so the app can show
 * the summary at the end ("Sovitut muutokset") and save it.
 */
public struct MeetingChangeLog: Equatable, Sendable {
  public var startedAt: Date

  public init(startedAt: Date) {
    self.startedAt = startedAt
  }

  public func changes(in state: FamilyState) -> [String] {
    state.history
      .filter { $0.date >= startedAt }
      .sorted { $0.date < $1.date }
      .compactMap { entry in
        let title = state.subjectTitle(entry.subject)
        let to = state.member(entry.toID)?.name
        let from = state.member(entry.fromID)?.name
        switch entry.kind {
        case .transferred: return "\(title): \(from ?? "avoin") → \(to ?? "avoin")"
        case .transferRequested: return "\(title): pyyntö \(to ?? "") odottaa vastausta"
        case .taken: return "\(title): \(to ?? "") otti hoitaakseen"
        case .released: return "\(title): avattiin kenen tahansa otettavaksi"
        case .completed: return "\(title): kuitattu hoidetuksi"
        case .helpRequested: return "\(title): pyydetty apua (\(entry.note ?? ""))"
        case .created: return entry.note == "Vuosikello" ? nil : "Uusi: \(title)"
        case .transferDeclined, .transferCancelled, .returned, .reopened: return nil
        }
      }
  }
}
