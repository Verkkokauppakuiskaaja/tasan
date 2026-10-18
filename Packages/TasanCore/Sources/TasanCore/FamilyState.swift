import Foundation

/// Identifies one synced record, for the sync engine's outbox.
public struct RecordRef: Hashable, Codable, Sendable {
  public var type: String
  public var id: UUID

  public init(type: String, id: UUID) {
    self.type = type
    self.id = id
  }

  /// CloudKit record name: "<type>.<uuid>".
  public var recordName: String { "\(type).\(id.uuidString)" }

  public init?(recordName: String) {
    let parts = recordName.split(separator: ".", maxSplits: 1).map(String.init)
    guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
    self.init(type: parts[0], id: id)
  }
}

/*
 * Everything one family has. All rule code mutates a FamilyState
 * through `save`/`delete`, which stamp `modifiedAt` and record the
 * change so the app can persist it and hand it to CloudKit.
 */
public struct FamilyState: Codable, Equatable, Sendable {
  public var family: Family?
  public var members: [Member] = []
  public var areas: [Area] = []
  public var templates: [YearTemplate] = []
  public var tasks: [FamilyTask] = []
  public var transfers: [TransferRequest] = []
  public var history: [HistoryEntry] = []
  public var meetings: [MeetingRecord] = []
  public var busy: [SharedBusy] = []

  /// Records changed locally and not yet confirmed by the server.
  public var pendingSaves: Set<RecordRef> = []
  public var pendingDeletes: Set<RecordRef> = []

  public init() {}

  // MARK: Lookup

  public func member(_ id: UUID?) -> Member? {
    guard let id else { return nil }
    return members.first { $0.id == id }
  }

  public func area(_ id: UUID?) -> Area? {
    guard let id else { return nil }
    return areas.first { $0.id == id }
  }

  public func task(_ id: UUID?) -> FamilyTask? {
    guard let id else { return nil }
    return tasks.first { $0.id == id }
  }

  public var adults: [Member] { members.filter { $0.role.isAdult } }
  public var children: [Member] { members.filter { $0.role == .child || $0.role == .teen } }
  public var responsibleCandidates: [Member] { members.filter { $0.role.canTakeResponsibility } }

  /// Everyone's shared busy blocks, for overlap detection.
  public var busyIntervals: [BusyInterval] { busy.flatMap(\.busyIntervals) }

  public func subtasks(of taskID: UUID) -> [FamilyTask] {
    tasks.filter { $0.parentTaskID == taskID }
  }

  public func history(for subject: TransferSubject) -> [HistoryEntry] {
    history.filter { $0.subject == subject }.sorted { $0.date < $1.date }
  }

  public func pendingTransfers(to memberID: UUID) -> [TransferRequest] {
    transfers.filter { $0.toID == memberID && $0.status == .pending }
  }

  public func pendingTransfer(for subject: TransferSubject) -> TransferRequest? {
    transfers.first { $0.subject == subject && $0.status == .pending }
  }

  // MARK: Mutation

  public mutating func save<R: FamilyRecord>(_ record: R, now: Date = Date()) {
    var record = record
    record.modifiedAt = now
    replace(record)
    let ref = RecordRef(type: R.recordType, id: record.id)
    pendingSaves.insert(ref)
    pendingDeletes.remove(ref)
  }

  public mutating func delete<R: FamilyRecord>(_ type: R.Type, id: UUID) {
    remove(type: R.recordType, id: id)
    let ref = RecordRef(type: R.recordType, id: id)
    pendingSaves.remove(ref)
    pendingDeletes.insert(ref)
  }

  /// Applies a record that came from the server. Keeps the local copy if it is newer.
  @discardableResult
  public mutating func applyRemote<R: FamilyRecord>(_ record: R) -> Bool {
    if let local: R = existing(R.self, id: record.id), local.modifiedAt > record.modifiedAt {
      return false
    }
    replace(record)
    pendingSaves.remove(RecordRef(type: R.recordType, id: record.id))
    return true
  }

  public mutating func applyRemoteDeletion(_ ref: RecordRef) {
    remove(type: ref.type, id: ref.id)
    pendingSaves.remove(ref)
    pendingDeletes.remove(ref)
  }

  public func encodedRecord(_ ref: RecordRef) throws -> Data? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    switch ref.type {
    case Family.recordType: return try family.flatMap { $0.id == ref.id ? try encoder.encode($0) : nil }
    case Member.recordType: return try members.first { $0.id == ref.id }.map(encoder.encode)
    case Area.recordType: return try areas.first { $0.id == ref.id }.map(encoder.encode)
    case YearTemplate.recordType: return try templates.first { $0.id == ref.id }.map(encoder.encode)
    case FamilyTask.recordType: return try tasks.first { $0.id == ref.id }.map(encoder.encode)
    case TransferRequest.recordType: return try transfers.first { $0.id == ref.id }.map(encoder.encode)
    case HistoryEntry.recordType: return try history.first { $0.id == ref.id }.map(encoder.encode)
    case MeetingRecord.recordType: return try meetings.first { $0.id == ref.id }.map(encoder.encode)
    case SharedBusy.recordType: return try busy.first { $0.id == ref.id }.map(encoder.encode)
    default: return nil
    }
  }

  /// Decodes a server payload and applies it. Returns false for unknown types or stale data.
  @discardableResult
  public mutating func applyRemotePayload(type: String, data: Data) throws -> Bool {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    switch type {
    case Family.recordType: return applyRemote(try decoder.decode(Family.self, from: data))
    case Member.recordType: return applyRemote(try decoder.decode(Member.self, from: data))
    case Area.recordType: return applyRemote(try decoder.decode(Area.self, from: data))
    case YearTemplate.recordType: return applyRemote(try decoder.decode(YearTemplate.self, from: data))
    case FamilyTask.recordType: return applyRemote(try decoder.decode(FamilyTask.self, from: data))
    case TransferRequest.recordType: return applyRemote(try decoder.decode(TransferRequest.self, from: data))
    case HistoryEntry.recordType: return applyRemote(try decoder.decode(HistoryEntry.self, from: data))
    case MeetingRecord.recordType: return applyRemote(try decoder.decode(MeetingRecord.self, from: data))
    case SharedBusy.recordType: return applyRemote(try decoder.decode(SharedBusy.self, from: data))
    default: return false
    }
  }

  /// Every record, for the first upload after creating a family.
  public var allRefs: [RecordRef] {
    var refs: [RecordRef] = []
    if let family { refs.append(RecordRef(type: Family.recordType, id: family.id)) }
    refs += members.map { RecordRef(type: Member.recordType, id: $0.id) }
    refs += areas.map { RecordRef(type: Area.recordType, id: $0.id) }
    refs += templates.map { RecordRef(type: YearTemplate.recordType, id: $0.id) }
    refs += tasks.map { RecordRef(type: FamilyTask.recordType, id: $0.id) }
    refs += transfers.map { RecordRef(type: TransferRequest.recordType, id: $0.id) }
    refs += history.map { RecordRef(type: HistoryEntry.recordType, id: $0.id) }
    refs += meetings.map { RecordRef(type: MeetingRecord.recordType, id: $0.id) }
    refs += busy.map { RecordRef(type: SharedBusy.recordType, id: $0.id) }
    return refs
  }

  // MARK: Storage helpers

  private func existing<R: FamilyRecord>(_ type: R.Type, id: UUID) -> R? {
    switch R.recordType {
    case Family.recordType: return family.flatMap { $0.id == id ? $0 as? R : nil }
    case Member.recordType: return members.first { $0.id == id } as? R
    case Area.recordType: return areas.first { $0.id == id } as? R
    case YearTemplate.recordType: return templates.first { $0.id == id } as? R
    case FamilyTask.recordType: return tasks.first { $0.id == id } as? R
    case TransferRequest.recordType: return transfers.first { $0.id == id } as? R
    case HistoryEntry.recordType: return history.first { $0.id == id } as? R
    case MeetingRecord.recordType: return meetings.first { $0.id == id } as? R
    case SharedBusy.recordType: return busy.first { $0.id == id } as? R
    default: return nil
    }
  }

  private mutating func replace<R: FamilyRecord>(_ record: R) {
    switch record {
    case let value as Family: family = value
    case let value as Member: Self.upsert(value, in: &members)
    case let value as Area: Self.upsert(value, in: &areas)
    case let value as YearTemplate: Self.upsert(value, in: &templates)
    case let value as FamilyTask: Self.upsert(value, in: &tasks)
    case let value as TransferRequest: Self.upsert(value, in: &transfers)
    case let value as HistoryEntry: Self.upsert(value, in: &history)
    case let value as MeetingRecord: Self.upsert(value, in: &meetings)
    case let value as SharedBusy: Self.upsert(value, in: &busy)
    default: break
    }
  }

  private mutating func remove(type: String, id: UUID) {
    switch type {
    case Family.recordType: if family?.id == id { family = nil }
    case Member.recordType: members.removeAll { $0.id == id }
    case Area.recordType: areas.removeAll { $0.id == id }
    case YearTemplate.recordType: templates.removeAll { $0.id == id }
    case FamilyTask.recordType: tasks.removeAll { $0.id == id }
    case TransferRequest.recordType: transfers.removeAll { $0.id == id }
    case HistoryEntry.recordType: history.removeAll { $0.id == id }
    case MeetingRecord.recordType: meetings.removeAll { $0.id == id }
    case SharedBusy.recordType: busy.removeAll { $0.id == id }
    default: break
    }
  }

  private static func upsert<R: FamilyRecord>(_ record: R, in list: inout [R]) {
    if let index = list.firstIndex(where: { $0.id == record.id }) {
      list[index] = record
    } else {
      list.append(record)
    }
  }
}
