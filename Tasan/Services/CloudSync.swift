import CloudKit
import Foundation
import TasanCore
import os

/*
 * Family sharing without our own server.
 *
 * The adult who creates the family owns a record zone in their
 * private CloudKit database and shares the whole zone with the
 * other adult (CKShare on the zone). The other adult sees the same
 * zone through their shared database. Both phones run a
 * CKSyncEngine against the database where the zone lives, so
 * pushes, batching and retries are handled by the system.
 *
 * Each FamilyRecord becomes one CKRecord whose "payload" field is
 * the record's JSON. Conflicts go to the newer `modifiedAt`.
 */
final class CloudSync: CKSyncEngineDelegate, @unchecked Sendable {
  enum Role: String, Codable {
    case owner
    case participant
  }

  struct Configuration: Codable {
    var role: Role
    var zoneName: String
    var zoneOwnerName: String
    var engineState: CKSyncEngine.State.Serialization?
    /// Last known server record per record name, so updates carry the right change tag.
    var systemFields: [String: Data] = [:]

    var zoneID: CKRecordZone.ID {
      CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
    }
  }

  /// Called on the main actor with what changed on the server.
  struct Handlers {
    var readState: @MainActor () -> FamilyState
    var applyRemote: @MainActor (_ payloads: [(type: String, data: Data)], _ deletions: [RecordRef]) -> Void
    var confirmSent: @MainActor (_ saved: [RecordRef], _ deleted: [RecordRef]) -> Void
    var familyRemoved: @MainActor () -> Void
  }

  static let containerIdentifier = "iCloud.fi.tasan.app"
  static let payloadKey = "payload"

  let container = CKContainer(identifier: CloudSync.containerIdentifier)
  private let logger = Logger(subsystem: "fi.tasan.app", category: "sync")
  private let configURL: URL
  private let handlers: Handlers
  private let lock = NSLock()
  private var configuration: Configuration?
  private var engine: CKSyncEngine?

  init(handlers: Handlers) {
    self.handlers = handlers
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    configURL = directory.appendingPathComponent("sync.json")
    if let data = try? Data(contentsOf: configURL) {
      configuration = try? JSONDecoder().decode(Configuration.self, from: data)
    }
  }

  var isConfigured: Bool { withConfig { $0 != nil } }
  var role: Role? { withConfig { $0?.role } }

  // MARK: Start

  /// Resumes syncing on launch if this phone already belongs to a family.
  func startIfConfigured() {
    guard let configuration = withConfig({ $0 }) else { return }
    startEngine(configuration)
  }

  /// The creating adult: make the family zone and upload everything.
  func startAsOwner(familyID: UUID, initialRecords: [RecordRef]) async throws {
    let zoneID = CKRecordZone.ID(zoneName: "Family-\(familyID.uuidString)", ownerName: CKCurrentUserDefaultName)
    _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    let configuration = Configuration(role: .owner, zoneName: zoneID.zoneName, zoneOwnerName: zoneID.ownerName)
    store(configuration)
    startEngine(configuration)
    enqueue(saves: initialRecords, deletes: [])
  }

  /// The invited adult opened the share link.
  func accept(_ metadata: CKShare.Metadata) async throws {
    _ = try await container.accept(metadata)
    let zoneID = metadata.share.recordID.zoneID
    let configuration = Configuration(role: .participant, zoneName: zoneID.zoneName, zoneOwnerName: zoneID.ownerName)
    store(configuration)
    startEngine(configuration)
    try await engine?.fetchChanges()
  }

  func currentUserRecordName() async -> String? {
    try? await container.userRecordID().recordName
  }

  // MARK: Changes

  func enqueue(saves: [RecordRef], deletes: [RecordRef]) {
    guard let engine, let zoneID = withConfig({ $0?.zoneID }) else { return }
    var changes: [CKSyncEngine.PendingRecordZoneChange] = []
    changes += saves.map { .saveRecord(CKRecord.ID(recordName: $0.recordName, zoneID: zoneID)) }
    changes += deletes.map { .deleteRecord(CKRecord.ID(recordName: $0.recordName, zoneID: zoneID)) }
    guard !changes.isEmpty else { return }
    engine.state.add(pendingRecordZoneChanges: changes)
  }

  func syncNow() async {
    try? await engine?.fetchChanges()
    try? await engine?.sendChanges()
  }

  // MARK: Sharing

  /// The zone-wide share the owner sends to the other adult.
  func familyShare(title: String) async throws -> CKShare {
    guard let configuration = withConfig({ $0 }), configuration.role == .owner else {
      throw CKError(.permissionFailure)
    }
    let database = container.privateCloudDatabase
    let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: configuration.zoneID)
    if let existing = try? await database.record(for: shareID) as? CKShare {
      return existing
    }
    let share = CKShare(recordZoneID: configuration.zoneID)
    share[CKShare.SystemFieldKey.title] = title
    share.publicPermission = .none
    let result = try await database.modifyRecords(saving: [share], deleting: [])
    if case let .success(saved)? = result.saveResults[shareID], let savedShare = saved as? CKShare {
      return savedShare
    }
    return share
  }

  /// Leaves the family on this phone. The owner deletes the zone, which ends sharing for everyone.
  func leave() async {
    if let configuration = withConfig({ $0 }) {
      if configuration.role == .owner {
        _ = try? await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [configuration.zoneID])
      } else {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: configuration.zoneID)
        _ = try? await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
      }
    }
    engine = nil
    store(nil)
  }

  // MARK: CKSyncEngineDelegate

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    switch event {
    case let .stateUpdate(update):
      mutateConfig { $0?.engineState = update.stateSerialization }

    case let .accountChange(change):
      switch change.changeType {
      case .signOut, .switchAccounts:
        logger.info("iCloud account changed, leaving family on this phone")
        await MainActor.run { handlers.familyRemoved() }
        engine = nil
        store(nil)
      default:
        break
      }

    case let .fetchedDatabaseChanges(changes):
      let zoneID = withConfig { $0?.zoneID }
      if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
        await MainActor.run { handlers.familyRemoved() }
        engine = nil
        store(nil)
      }

    case let .fetchedRecordZoneChanges(changes):
      let records = changes.modifications.map(\.record)
      cacheSystemFields(records)
      let payloads = records.compactMap { record -> (type: String, data: Data)? in
        guard let data = record[Self.payloadKey] as? Data else { return nil }
        return (record.recordType, data)
      }
      let deletions = changes.deletions.compactMap { RecordRef(recordName: $0.recordID.recordName) }
      mutateConfig { config in
        for deletion in changes.deletions { config?.systemFields[deletion.recordID.recordName] = nil }
      }
      await MainActor.run { handlers.applyRemote(payloads, deletions) }

    case let .sentRecordZoneChanges(sent):
      cacheSystemFields(sent.savedRecords)
      let saved = sent.savedRecords.compactMap { RecordRef(recordName: $0.recordID.recordName) }
      let deleted = sent.deletedRecordIDs.compactMap { RecordRef(recordName: $0.recordName) }
      await MainActor.run { handlers.confirmSent(saved, deleted) }
      await handleFailures(sent.failedRecordSaves, syncEngine: syncEngine)

    default:
      break
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let scope = context.options.scope
    let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
    guard !changes.isEmpty else { return nil }
    let state = await MainActor.run { handlers.readState() }

    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      guard let ref = RecordRef(recordName: recordID.recordName),
        let payload = try? state.encodedRecord(ref)
      else {
        // The record was deleted locally after it was queued.
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      }
      let record = self.cachedRecord(for: recordID) ?? CKRecord(recordType: ref.type, recordID: recordID)
      record[Self.payloadKey] = payload as NSData
      return record
    }
  }

  // MARK: Private

  private func handleFailures(_ failures: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave], syncEngine: CKSyncEngine) async {
    var requeue: [CKSyncEngine.PendingRecordZoneChange] = []
    var needsZone = false

    for failure in failures {
      let recordID = failure.record.recordID
      switch failure.error.code {
      case .serverRecordChanged:
        guard let server = failure.error.serverRecord else { continue }
        cacheSystemFields([server])
        if let data = server[Self.payloadKey] as? Data {
          // applyRemote keeps the local copy when it is newer; then our version goes up again.
          await MainActor.run { handlers.applyRemote([(server.recordType, data)], []) }
          let stillPending = await MainActor.run {
            handlers.readState().pendingSaves.contains { $0.recordName == recordID.recordName }
          }
          if stillPending { requeue.append(.saveRecord(recordID)) }
        }
      case .zoneNotFound:
        needsZone = true
        requeue.append(.saveRecord(recordID))
      case .unknownItem:
        mutateConfig { $0?.systemFields[recordID.recordName] = nil }
        requeue.append(.saveRecord(recordID))
      case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
        // CKSyncEngine retries these on its own.
        break
      default:
        logger.error("Saving \(recordID.recordName) failed: \(failure.error.localizedDescription)")
      }
    }

    if needsZone, let zoneID = withConfig({ $0?.role == .owner ? $0?.zoneID : nil }) {
      syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }
    if !requeue.isEmpty {
      syncEngine.state.add(pendingRecordZoneChanges: requeue)
    }
  }

  private func startEngine(_ configuration: Configuration) {
    let database = configuration.role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
    var engineConfiguration = CKSyncEngine.Configuration(
      database: database,
      stateSerialization: configuration.engineState,
      delegate: self
    )
    engineConfiguration.automaticallySync = true
    engine = CKSyncEngine(engineConfiguration)
  }

  private func cachedRecord(for recordID: CKRecord.ID) -> CKRecord? {
    guard let data = withConfig({ $0?.systemFields[recordID.recordName] }),
      let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
    else { return nil }
    coder.requiresSecureCoding = true
    defer { coder.finishDecoding() }
    return CKRecord(coder: coder)
  }

  private func cacheSystemFields(_ records: [CKRecord]) {
    var encoded: [String: Data] = [:]
    for record in records {
      let coder = NSKeyedArchiver(requiringSecureCoding: true)
      record.encodeSystemFields(with: coder)
      coder.finishEncoding()
      encoded[record.recordID.recordName] = coder.encodedData
    }
    mutateConfig { config in
      for (name, data) in encoded { config?.systemFields[name] = data }
    }
  }

  private func withConfig<T>(_ body: (Configuration?) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body(configuration)
  }

  private func mutateConfig(_ body: (inout Configuration?) -> Void) {
    lock.lock()
    body(&configuration)
    let snapshot = configuration
    lock.unlock()
    persist(snapshot)
  }

  private func store(_ configuration: Configuration?) {
    lock.lock()
    self.configuration = configuration
    lock.unlock()
    persist(configuration)
  }

  private func persist(_ configuration: Configuration?) {
    guard let configuration else {
      try? FileManager.default.removeItem(at: configURL)
      return
    }
    if let data = try? JSONEncoder().encode(configuration) {
      try? data.write(to: configURL, options: .atomic)
    }
  }
}
