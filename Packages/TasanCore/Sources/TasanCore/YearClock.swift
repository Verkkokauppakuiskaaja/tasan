import Foundation

/*
 * The year clock turns templates into tasks before anyone has to
 * remember them. A task is created once its preparation day comes
 * within `horizonDays`, it goes to the owner of the matching area,
 * and the occurrence key makes sure a template creates each
 * occurrence only once, even if the task is later deleted
 * or skipped.
 */
public struct YearClock {
  public var horizonDays: Int

  public init(horizonDays: Int = 45) {
    self.horizonDays = horizonDays
  }

  public struct Occurrence: Equatable, Sendable {
    public var template: YearTemplate
    public var eventDay: Day
    public var prepDay: Day
    public var memberID: UUID?
    public var key: String
  }

  /// All occurrences whose event day is within the window [from, to].
  public func occurrences(in state: FamilyState, from: Day, to: Day) -> [Occurrence] {
    guard let family = state.family else { return [] }
    let enabledKinds = Set(state.areas.filter(\.enabled).map(\.kind))
    let children = state.children
    var result: [Occurrence] = []

    for template in state.templates where template.enabled && enabledKinds.contains(template.areaKind) {
      for year in from.year...to.year {
        for (eventDay, birthdayMember) in template.rule.days(in: year, family: family, children: children) {
          guard eventDay >= from, eventDay <= to else { continue }
          let prepDay = eventDay.adding(days: -template.leadDays)
          let memberIDs: [UUID?]
          if let birthdayMember {
            memberIDs = [birthdayMember]
          } else if template.scope == .perChild {
            memberIDs = children.map(\.id)
          } else {
            memberIDs = [nil]
          }
          for memberID in memberIDs {
            result.append(
              Occurrence(
                template: template,
                eventDay: eventDay,
                prepDay: prepDay,
                memberID: memberID,
                key: Self.key(template: template, eventDay: eventDay, memberID: memberID)
              )
            )
          }
        }
      }
    }
    return result.sorted { ($0.prepDay, $0.template.title) < ($1.prepDay, $1.template.title) }
  }

  /// modifiedAt for records both phones may generate independently.
  public static let generatedStamp = Date(timeIntervalSince1970: 1)

  public static func key(template: YearTemplate, eventDay: Day, memberID: UUID?) -> String {
    let templateKey = template.builtInKey ?? template.id.uuidString
    return "\(templateKey)|\(eventDay.year)|\(memberID?.uuidString ?? "-")"
  }

  /// Creates the tasks that are due by now. Returns the created tasks.
  @discardableResult
  public func generateTasks(in state: inout FamilyState, today: Day, actorID: UUID?, now: Date = Date()) -> [FamilyTask] {
    let existingKeys = Set(state.tasks.compactMap(\.occurrenceKey))
    let horizonEnd = today.adding(days: horizonDays)
    // The event may be far away even when its preparation is near (summer care, 60 days).
    let maxLead = state.templates.map(\.leadDays).max() ?? 0
    let candidates = occurrences(in: state, from: today, to: horizonEnd.adding(days: maxLead))

    var created: [FamilyTask] = []
    for occurrence in candidates where occurrence.prepDay <= horizonEnd && !existingKeys.contains(occurrence.key) {
      created.append(Self.createTask(for: occurrence, in: &state, today: today, actorID: actorID, now: now))
    }
    return created
  }

  /*
   * One occurrence as a task. Also used by the monthly meeting to
   * create a coming task early ("Luo nyt"); the id is the same as
   * the year clock would give it later, so nothing is duplicated.
   */
  @discardableResult
  public static func createTask(for occurrence: Occurrence, in state: inout FamilyState, today: Day, actorID: UUID?, now: Date = Date()) -> FamilyTask {
    let area = area(for: occurrence.template.areaKind, subject: occurrence.memberID, in: state)
    let subjectName = state.member(occurrence.memberID)?.name
    let title = subjectName.map { "\(occurrence.template.title): \($0)" } ?? occurrence.template.title
    let familyID = state.family?.id.uuidString ?? ""
    let task = FamilyTask(
      id: UUID(deterministic: "\(familyID)|task|\(occurrence.key)"),
      title: title,
      notes: occurrence.template.notes,
      areaID: area?.id,
      responsibleID: area?.ownerID,
      subjectMemberID: occurrence.memberID,
      eventDay: occurrence.eventDay,
      prepDay: max(occurrence.prepDay, today),
      source: .yearClock,
      templateID: occurrence.template.id,
      occurrenceKey: occurrence.key,
      createdAt: now
    )
    // An old stamp: if the other phone already created and edited this task, its edits win.
    state.save(task, now: generatedStamp)
    state.save(
      HistoryEntry(
        id: UUID(deterministic: "\(familyID)|created|\(occurrence.key)"),
        subject: .task(task.id), kind: .created, actorID: actorID, toID: task.responsibleID, note: "Vuosikello", date: now
      ),
      now: generatedStamp
    )
    return task
  }

  /// The most specific enabled area: one narrowed to the child first, then the general one.
  public static func area(for kind: AreaKind, subject: UUID?, in state: FamilyState) -> Area? {
    let areas = state.areas.filter { $0.kind == kind && $0.enabled }
    if let subject, let specific = areas.first(where: { $0.subjectMemberID == subject }) {
      return specific
    }
    return areas.first { $0.subjectMemberID == nil } ?? areas.first
  }

  /// Year clock overview for one month, for the Vuosikello screen.
  public func monthOverview(in state: FamilyState, year: Int, month: Int) -> [Occurrence] {
    let from = Day(year, month, 1)
    let to = Day(year, month, Day.daysInMonth(month, year: year))
    return occurrences(in: state, from: from, to: to).sorted { $0.eventDay < $1.eventDay }
  }
}
