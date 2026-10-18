import Foundation

/*
 * Every synced entity is a Codable value with a stable id and a
 * modification stamp. The app stores them locally as JSON and
 * syncs each one as a CloudKit record; when both phones change
 * the same record, the later `modifiedAt` wins.
 */
public protocol FamilyRecord: Codable, Identifiable, Equatable, Sendable where ID == UUID {
  static var recordType: String { get }
  var id: UUID { get }
  var modifiedAt: Date { get set }
}

// MARK: - Family

public struct Family: FamilyRecord {
  public static let recordType = "Family"

  public var id: UUID
  public var name: String
  /// Lets an admin move a responsibility without the receiver's approval. Off by default.
  public var adminDirectTransferEnabled: Bool
  public var weeklyMeeting: MeetingSchedule
  public var monthlyMeetingEnabled: Bool
  /// School winter holiday week ("hiihtoloma") varies by municipality: week 8, 9 or 10.
  public var winterHolidayWeek: Int
  public var createdAt: Date
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    adminDirectTransferEnabled: Bool = false,
    weeklyMeeting: MeetingSchedule = MeetingSchedule(),
    monthlyMeetingEnabled: Bool = true,
    winterHolidayWeek: Int = 9,
    createdAt: Date = Date(),
    modifiedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.adminDirectTransferEnabled = adminDirectTransferEnabled
    self.weeklyMeeting = weeklyMeeting
    self.monthlyMeetingEnabled = monthlyMeetingEnabled
    self.winterHolidayWeek = winterHolidayWeek
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
  }
}

public struct MeetingSchedule: Codable, Equatable, Sendable {
  /// ISO weekday, 7 = Sunday.
  public var weekday: Int
  /// Minutes after midnight, 19:00 by default.
  public var minutes: Int
  public var enabled: Bool

  public init(weekday: Int = 7, minutes: Int = 19 * 60, enabled: Bool = true) {
    self.weekday = weekday
    self.minutes = minutes
    self.enabled = enabled
  }
}

// MARK: - Members

public enum MemberRole: String, Codable, CaseIterable, Sendable {
  case adminAdult
  case adult
  case child
  /// Teens, grandparents and sitters come in 1.2; the cases exist so data stays forward compatible.
  case teen
  case helper

  public var canTakeResponsibility: Bool {
    switch self {
    case .adminAdult, .adult: return true
    case .child, .teen, .helper: return false
    }
  }

  public var isAdmin: Bool { self == .adminAdult }
  public var isAdult: Bool { self == .adminAdult || self == .adult }
}

public struct Member: FamilyRecord {
  public static let recordType = "Member"

  public var id: UUID
  public var name: String
  public var colorHex: String
  public var role: MemberRole
  public var birthday: Day?
  public var clothingSize: String?
  public var shoeSize: String?
  public var school: String?
  public var schoolClass: String?
  public var hobbies: [String]
  /// The CloudKit user record name of the adult who uses this profile, set when they join.
  public var cloudUserID: String?
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    colorHex: String,
    role: MemberRole,
    birthday: Day? = nil,
    clothingSize: String? = nil,
    shoeSize: String? = nil,
    school: String? = nil,
    schoolClass: String? = nil,
    hobbies: [String] = [],
    cloudUserID: String? = nil,
    modifiedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.role = role
    self.birthday = birthday
    self.clothingSize = clothingSize
    self.shoeSize = shoeSize
    self.school = school
    self.schoolClass = schoolClass
    self.hobbies = hobbies
    self.cloudUserID = cloudUserID
    self.modifiedAt = modifiedAt
  }

  public static let palette = ["2560F5", "EC602F", "16A349", "9B51E0", "F2A900", "0FA3B1", "E0457B"]
}

// MARK: - Areas

/// The five MVP areas of family meta-work.
public enum AreaKind: String, Codable, CaseIterable, Sendable {
  case clothing
  case school
  case hobbies
  case parties
  case holidays

  public var title: String {
    switch self {
    case .clothing: return "Vaatteet ja varusteet"
    case .school: return "Koulu ja päiväkoti"
    case .hobbies: return "Harrastukset"
    case .parties: return "Synttärit ja juhlat"
    case .holidays: return "Juhlapyhät"
    }
  }

  public var symbolName: String {
    switch self {
    case .clothing: return "tshirt.fill"
    case .school: return "backpack.fill"
    case .hobbies: return "figure.soccer"
    case .parties: return "gift.fill"
    case .holidays: return "star.fill"
    }
  }

  /// Default preparation lead, days before the event, when a task has no template.
  public var defaultLeadDays: Int {
    switch self {
    case .clothing: return 21
    case .school: return 3
    case .hobbies: return 7
    case .parties: return 7
    case .holidays: return 14
    }
  }
}

/*
 * An area ("osa-alue") is a standing responsibility. There is one
 * per kind by default, and the family can add narrower ones such
 * as "Liisan harrastukset" by giving an area a subject member.
 */
public struct Area: FamilyRecord {
  public static let recordType = "Area"

  public var id: UUID
  public var kind: AreaKind
  public var name: String
  /// New tasks in this area go to the owner. nil = nobody owns it yet.
  public var ownerID: UUID?
  /// Narrows the area to one child, e.g. "Liisan harrastukset".
  public var subjectMemberID: UUID?
  public var enabled: Bool
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    kind: AreaKind,
    name: String? = nil,
    ownerID: UUID? = nil,
    subjectMemberID: UUID? = nil,
    enabled: Bool = true,
    modifiedAt: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.name = name ?? kind.title
    self.ownerID = ownerID
    self.subjectMemberID = subjectMemberID
    self.enabled = enabled
    self.modifiedAt = modifiedAt
  }
}

// MARK: - Year clock templates

/// Who a template creates tasks for.
public enum TemplateScope: String, Codable, Sendable {
  /// One task for the whole family.
  case family
  /// One task per child ("Toppahaalarin koko: Liisa", "Toppahaalarin koko: Eetu").
  case perChild
}

public struct YearTemplate: FamilyRecord {
  public static let recordType = "YearTemplate"

  public var id: UUID
  /// Stable key for built-in templates so updates and dedupe survive edits.
  public var builtInKey: String?
  public var areaKind: AreaKind
  public var title: String
  public var notes: String?
  public var rule: YearRule
  /// Days between the preparation day and the event day.
  public var leadDays: Int
  public var scope: TemplateScope
  public var enabled: Bool
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    builtInKey: String? = nil,
    areaKind: AreaKind,
    title: String,
    notes: String? = nil,
    rule: YearRule,
    leadDays: Int,
    scope: TemplateScope = .family,
    enabled: Bool = true,
    modifiedAt: Date = Date()
  ) {
    self.id = id
    self.builtInKey = builtInKey
    self.areaKind = areaKind
    self.title = title
    self.notes = notes
    self.rule = rule
    self.leadDays = leadDays
    self.scope = scope
    self.enabled = enabled
    self.modifiedAt = modifiedAt
  }
}

// MARK: - Tasks

public enum TaskStatus: String, Codable, Sendable {
  case open
  case done
  /// "Ohita tänä vuonna": a year clock task the family does not need. Kept so it is not recreated.
  case skipped
}

public enum TaskSource: String, Codable, Sendable {
  case manual
  case yearClock
  case image
}

/// A transfer that undoes itself: the task goes back to `memberID` on `day`.
public struct TemporaryReturn: Codable, Equatable, Sendable {
  public var memberID: UUID
  public var day: Day

  public init(memberID: UUID, day: Day) {
    self.memberID = memberID
    self.day = day
  }
}

/*
 * A task has exactly one responsible adult who remembers, plans
 * and does it. `responsibleID == nil` makes it an open task that
 * anyone can take. The event day and the preparation day are two
 * separate entries in the calendar: the party is on Saturday, the
 * present is bought on Thursday.
 */
public struct FamilyTask: FamilyRecord {
  public static let recordType = "FamilyTask"

  public var id: UUID
  public var title: String
  public var notes: String?
  public var areaID: UUID?
  public var responsibleID: UUID?
  /// The child or member the task is about, if any.
  public var subjectMemberID: UUID?
  public var eventDay: Day?
  /// Minutes after midnight; nil = all-day.
  public var eventMinutes: Int?
  public var eventDurationMinutes: Int?
  public var location: String?
  public var prepDay: Day?
  /// Reminder moment for the responsible person. nil = prep day at 9:00 by default.
  public var reminder: Date?
  public var status: TaskStatus
  public var source: TaskSource
  public var templateID: UUID?
  /// "<template>|<year>|<member>" for year clock tasks, so a template never creates the same task twice.
  public var occurrenceKey: String?
  public var temporaryReturn: TemporaryReturn?
  /// Set for a "Pyydä apua" sub-task: the parent's responsibility stays where it is.
  public var parentTaskID: UUID?
  public var createdAt: Date
  public var completedAt: Date?
  public var completedByID: UUID?
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    title: String,
    notes: String? = nil,
    areaID: UUID? = nil,
    responsibleID: UUID? = nil,
    subjectMemberID: UUID? = nil,
    eventDay: Day? = nil,
    eventMinutes: Int? = nil,
    eventDurationMinutes: Int? = nil,
    location: String? = nil,
    prepDay: Day? = nil,
    reminder: Date? = nil,
    status: TaskStatus = .open,
    source: TaskSource = .manual,
    templateID: UUID? = nil,
    occurrenceKey: String? = nil,
    temporaryReturn: TemporaryReturn? = nil,
    parentTaskID: UUID? = nil,
    createdAt: Date = Date(),
    completedAt: Date? = nil,
    completedByID: UUID? = nil,
    modifiedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.areaID = areaID
    self.responsibleID = responsibleID
    self.subjectMemberID = subjectMemberID
    self.eventDay = eventDay
    self.eventMinutes = eventMinutes
    self.eventDurationMinutes = eventDurationMinutes
    self.location = location
    self.prepDay = prepDay
    self.reminder = reminder
    self.status = status
    self.source = source
    self.templateID = templateID
    self.occurrenceKey = occurrenceKey
    self.temporaryReturn = temporaryReturn
    self.parentTaskID = parentTaskID
    self.createdAt = createdAt
    self.completedAt = completedAt
    self.completedByID = completedByID
    self.modifiedAt = modifiedAt
  }

  public var isOpenForTaking: Bool { responsibleID == nil && status == .open }

  /// The day the task needs attention: preparation first, otherwise the event itself.
  public var actionDay: Day? { prepDay ?? eventDay }

  /// When the reminder fires. Defaults to 9:00 on the action day.
  public func reminderDate(calendar: Calendar = .finnish) -> Date? {
    if let reminder { return reminder }
    return actionDay?.date(minutes: 9 * 60, calendar: calendar)
  }
}

// MARK: - Transfers

public enum TransferStatus: String, Codable, Sendable {
  case pending
  case accepted
  case declined
  case cancelled
}

public enum TransferSubject: Codable, Equatable, Sendable {
  case task(UUID)
  case area(UUID)
}

/*
 * "Siirrä vastuu": a request from the current responsible (or an
 * admin) to another adult. The receiver accepts or declines; an
 * admin may also move it directly when the family allows it.
 */
public struct TransferRequest: FamilyRecord {
  public static let recordType = "TransferRequest"

  public var id: UUID
  public var subject: TransferSubject
  public var fromID: UUID?
  public var toID: UUID
  public var requestedByID: UUID
  public var message: String?
  /// Temporary transfer: responsibility returns to `fromID` on this day.
  public var returnDay: Day?
  public var status: TransferStatus
  public var createdAt: Date
  public var resolvedAt: Date?
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    subject: TransferSubject,
    fromID: UUID?,
    toID: UUID,
    requestedByID: UUID,
    message: String? = nil,
    returnDay: Day? = nil,
    status: TransferStatus = .pending,
    createdAt: Date = Date(),
    resolvedAt: Date? = nil,
    modifiedAt: Date = Date()
  ) {
    self.id = id
    self.subject = subject
    self.fromID = fromID
    self.toID = toID
    self.requestedByID = requestedByID
    self.message = message
    self.returnDay = returnDay
    self.status = status
    self.createdAt = createdAt
    self.resolvedAt = resolvedAt
    self.modifiedAt = modifiedAt
  }
}

// MARK: - History

public enum HistoryKind: String, Codable, Sendable {
  case created
  case transferRequested
  case transferred
  case transferDeclined
  case transferCancelled
  case returned
  case taken
  case released
  case helpRequested
  case completed
  case reopened
}

public struct HistoryEntry: FamilyRecord {
  public static let recordType = "HistoryEntry"

  public var id: UUID
  public var subject: TransferSubject
  public var kind: HistoryKind
  public var actorID: UUID?
  public var fromID: UUID?
  public var toID: UUID?
  public var note: String?
  public var date: Date
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    subject: TransferSubject,
    kind: HistoryKind,
    actorID: UUID?,
    fromID: UUID? = nil,
    toID: UUID? = nil,
    note: String? = nil,
    date: Date = Date()
  ) {
    self.id = id
    self.subject = subject
    self.kind = kind
    self.actorID = actorID
    self.fromID = fromID
    self.toID = toID
    self.note = note
    self.date = date
    self.modifiedAt = date
  }
}

// MARK: - Meeting summary

public enum MeetingKind: String, Codable, Sendable {
  case weekly
  case monthly
}

/// What was agreed in a family meeting, kept so the next one can look back.
public struct MeetingRecord: FamilyRecord {
  public static let recordType = "MeetingRecord"

  public var id: UUID
  public var kind: MeetingKind
  public var date: Date
  public var participantIDs: [UUID]
  public var agreedChanges: [String]
  public var modifiedAt: Date

  public init(
    id: UUID = UUID(),
    kind: MeetingKind,
    date: Date = Date(),
    participantIDs: [UUID],
    agreedChanges: [String]
  ) {
    self.id = id
    self.kind = kind
    self.date = date
    self.participantIDs = participantIDs
    self.agreedChanges = agreedChanges
    self.modifiedAt = date
  }
}

// MARK: - Shared busy times

/*
 * Each adult's phone publishes the busy blocks of their own
 * calendars for the coming weeks, so the family calendar can show
 * everyone and overlaps can suggest who is free. Titles are shared
 * only if that adult allows it; otherwise the block reads "Varattu".
 */
public struct SharedBusy: FamilyRecord {
  public static let recordType = "SharedBusy"

  public struct Block: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var title: String?
    public var isAllDay: Bool

    public init(start: Date, end: Date, title: String?, isAllDay: Bool) {
      self.start = start
      self.end = end
      self.title = title
      self.isAllDay = isAllDay
    }
  }

  /// Same as the member id: one record per adult.
  public var id: UUID
  public var blocks: [Block]
  public var modifiedAt: Date

  public init(memberID: UUID, blocks: [Block], modifiedAt: Date = Date()) {
    self.id = memberID
    self.blocks = blocks
    self.modifiedAt = modifiedAt
  }

  public var busyIntervals: [BusyInterval] {
    blocks.filter { !$0.isAllDay }.map { BusyInterval(memberID: id, start: $0.start, end: $0.end, title: $0.title) }
  }
}
