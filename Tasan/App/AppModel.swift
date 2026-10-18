import CloudKit
import Foundation
import Observation
import SwiftUI
import TasanCore

enum AppTab: Hashable {
  case today
  case calendar
  case yearClock
  case load
  case meeting
}

/*
 * The app's single source of truth. Views read `state` and call
 * the action methods below; every change goes through `commit`,
 * which saves to disk, queues the change for CloudKit and then
 * brings this phone's calendars, reminders and badge up to date.
 */
@MainActor
@Observable
final class AppModel {
  private(set) var state: FamilyState
  private(set) var meID: UUID?
  var selectedTab: AppTab = .today
  var openedTaskID: UUID?
  var errorMessage: String?
  var isJoiningFamily = false
  private(set) var myEvents: [ExternalEvent] = []

  @ObservationIgnored private let store = FamilyStore()
  @ObservationIgnored private(set) var sync: CloudSync!
  @ObservationIgnored let calendars = CalendarSync()
  @ObservationIgnored let notifications = NotificationService()
  @ObservationIgnored private var followUp: Task<Void, Never>?

  init() {
    AppLanguage.install()
    state = store.load()
    meID = DeviceSettings.currentMemberID
    sync = CloudSync(
      handlers: CloudSync.Handlers(
        readState: { [weak self] in self?.state ?? FamilyState() },
        applyRemote: { [weak self] payloads, deletions in self?.applyRemote(payloads, deletions) },
        confirmSent: { [weak self] saved, deleted in self?.confirmSent(saved, deleted) },
        familyRemoved: { [weak self] in self?.familyRemoved() }
      )
    )
    notifications.onTransferAction = { [weak self] id, accept in
      if accept { self?.acceptTransfer(id) } else { self?.declineTransfer(id) }
    }
    notifications.onOpenTask = { [weak self] id in self?.open(taskID: id) }
    notifications.onOpenMeeting = { [weak self] in self?.selectedTab = .meeting }
  }

  // MARK: Derived

  var me: Member? { state.member(meID) }
  var hasFamily: Bool { state.family != nil && me != nil }
  var isAdmin: Bool { me?.role.isAdmin == true }
  var partner: Member? { state.adults.first { $0.id != meID } }
  var isOwner: Bool { sync.role == .owner }

  var myOpenTasks: [FamilyTask] {
    state.tasks.filter { $0.status == .open && $0.responsibleID == meID }
      .sorted { ($0.actionDay ?? .distant) < ($1.actionDay ?? .distant) }
  }

  var openTasks: [FamilyTask] {
    state.tasks.filter(\.isOpenForTaking).sorted { ($0.actionDay ?? .distant) < ($1.actionDay ?? .distant) }
  }

  var requestsToMe: [TransferRequest] {
    guard let meID else { return [] }
    return state.pendingTransfers(to: meID).sorted { $0.createdAt > $1.createdAt }
  }

  var myPendingRequests: [TransferRequest] {
    state.transfers.filter { $0.status == .pending && $0.requestedByID == meID }
  }

  var overlaps: [Overlap] {
    OverlapDetector.overlaps(in: state, busy: state.busyIntervals)
  }

  // MARK: Lifecycle

  func launch() {
    sync.startIfConfigured()
    runDailyMaintenanceIfNeeded()
    scheduleFollowUp(refreshBusy: true)
  }

  func becameActive() {
    runDailyMaintenanceIfNeeded()
    Task {
      await sync.syncNow()
      await refreshMyEvents()
    }
  }

  private func runDailyMaintenanceIfNeeded() {
    guard hasFamily else { return }
    let today = Day.today()
    guard DeviceSettings.lastMaintenanceDay != today.description else { return }
    DeviceSettings.lastMaintenanceDay = today.description
    commit { state in
      state.addMissingBuiltInTemplates()
      state.runDailyMaintenance(today: today, actorID: nil)
    }
  }

  // MARK: Committing changes

  /// Applies a change through the core rules. Shows the error and returns false when a rule says no.
  @discardableResult
  func commit(_ change: (inout FamilyState) throws -> Void) -> Bool {
    var draft = state
    do {
      try change(&draft)
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
    state = draft
    store.save(state)
    sync.enqueue(saves: Array(state.pendingSaves), deletes: Array(state.pendingDeletes))
    scheduleFollowUp(refreshBusy: false)
    return true
  }

  /// Calendar, reminders and notifications follow the data, a moment after the last change.
  private func scheduleFollowUp(refreshBusy: Bool) {
    followUp?.cancel()
    followUp = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard let self, !Task.isCancelled else { return }
      await self.calendars.reconcile(state: self.state, me: self.meID)
      await self.notifications.rescheduleReminders(state: self.state, me: self.meID)
      self.notifications.announceTransfers(state: self.state, me: self.meID)
      self.notifications.updateBadge(count: self.requestsToMe.count)
      await self.notifications.scheduleMeetingReminders(family: self.state.family)
      if refreshBusy { await self.refreshMyEvents() }
    }
  }

  private func applyRemote(_ payloads: [(type: String, data: Data)], _ deletions: [RecordRef]) {
    var changed = false
    for payload in payloads {
      changed = ((try? state.applyRemotePayload(type: payload.type, data: payload.data)) ?? false) || changed
    }
    for ref in deletions {
      state.applyRemoteDeletion(ref)
      changed = true
    }
    guard changed else { return }
    if meID == nil || state.member(meID) == nil {
      isJoiningFamily = state.family != nil
    }
    store.save(state)
    scheduleFollowUp(refreshBusy: false)
  }

  private func confirmSent(_ saved: [RecordRef], _ deleted: [RecordRef]) {
    state.pendingSaves.subtract(saved)
    state.pendingDeletes.subtract(deleted)
    store.save(state)
  }

  private func familyRemoved() {
    state = FamilyState()
    meID = nil
    DeviceSettings.currentMemberID = nil
    store.reset()
    calendars.forgetLinks()
    Task {
      await calendars.reconcile(state: state, me: nil)
      await notifications.rescheduleReminders(state: state, me: nil)
    }
  }

  // MARK: Family setup

  struct NewChild {
    var name: String
    var birthday: Date?
  }

  func createFamily(name: String, myName: String, myColor: String, children: [NewChild], enabledAreas: Set<AreaKind>) async {
    var admin = Member(name: myName, colorHex: myColor, role: .adminAdult)
    admin.cloudUserID = await sync.currentUserRecordName()
    var newState = FamilyState.newFamily(name: name, admin: admin, enabledAreas: enabledAreas)
    for (index, child) in children.enumerated() where !child.name.trimmingCharacters(in: .whitespaces).isEmpty {
      newState.save(
        Member(
          name: child.name,
          colorHex: Member.palette[(index + 2) % Member.palette.count],
          role: .child,
          birthday: child.birthday.map { Day(date: $0) }
        )
      )
    }
    newState.runDailyMaintenance(today: .today(), actorID: admin.id)
    DeviceSettings.lastMaintenanceDay = Day.today().description
    state = newState
    meID = admin.id
    DeviceSettings.currentMemberID = admin.id
    store.save(state)

    do {
      try await sync.startAsOwner(familyID: newState.family!.id, initialRecords: newState.allRefs)
    } catch {
      errorMessage = String(localized: "Perhe tallentui tähän puhelimeen, mutta iCloud-yhteys ei onnistunut: \(error.localizedDescription). Kirjaudu iCloudiin, niin voit kutsua toisen aikuisen.")
    }
    _ = await notifications.requestAuthorization()
    scheduleFollowUp(refreshBusy: false)
  }

  /// The share the owner sends to the other adult ("Kutsu aikuinen").
  func invitationShare() async throws -> CKShare {
    try await sync.familyShare(title: "Tasan! – \(state.family?.name ?? String(localized: "perhe"))")
  }

  /// Opened from the iCloud share link on the invited adult's phone.
  func acceptShare(_ metadata: CKShare.Metadata) async {
    guard !hasFamily else {
      errorMessage = String(localized: "Tämä puhelin kuuluu jo perheeseen. Poistu ensin nykyisestä perheestä asetuksissa.")
      return
    }
    isJoiningFamily = true
    do {
      try await sync.accept(metadata)
      // If this Apple ID already has a profile (reinstall), use it straight away.
      if let cloudID = await sync.currentUserRecordName(), let existing = state.members.first(where: { $0.cloudUserID == cloudID }) {
        claim(existing.id)
      }
    } catch {
      isJoiningFamily = false
      errorMessage = String(localized: "Kutsun avaaminen ei onnistunut: \(error.localizedDescription)")
    }
  }

  /// "Tämä olen minä": the joining adult picks their profile, or creates one.
  func claim(_ memberID: UUID?, newName: String? = nil, color: String = Member.palette[1]) {
    Task {
      let cloudID = await sync.currentUserRecordName()
      commit { state in
        var member = state.member(memberID) ?? Member(name: newName ?? String(localized: "Aikuinen"), colorHex: color, role: .adult)
        member.cloudUserID = cloudID
        if !member.role.isAdult { member.role = .adult }
        state.save(member)
      }
      let id = memberID ?? state.members.last { $0.cloudUserID == cloudID }?.id
      meID = id
      DeviceSettings.currentMemberID = id
      isJoiningFamily = false
      notifications.markAllTransfersSeen(state: state)
      _ = await notifications.requestAuthorization()
      scheduleFollowUp(refreshBusy: true)
    }
  }

  func leaveFamily() async {
    await sync.leave()
    familyRemoved()
  }

  // MARK: Tasks

  func save(_ task: FamilyTask, isNew: Bool) {
    commit { state in
      state.save(task)
      if isNew {
        state.save(HistoryEntry(subject: .task(task.id), kind: .created, actorID: meID, toID: task.responsibleID))
      }
    }
  }

  func delete(_ task: FamilyTask) {
    commit { state in
      for sub in state.subtasks(of: task.id) { state.delete(FamilyTask.self, id: sub.id) }
      if task.occurrenceKey != nil {
        // Year clock tasks are skipped, not deleted, so the template does not bring them back.
        try state.skip(task.id, actorID: meID ?? UUID())
      } else {
        state.delete(FamilyTask.self, id: task.id)
      }
    }
  }

  func complete(_ taskID: UUID) {
    guard let meID else { return }
    commit { try $0.complete(taskID, actorID: meID) }
  }

  func reopen(_ taskID: UUID) {
    guard let meID else { return }
    commit { try $0.reopen(taskID, actorID: meID) }
  }

  func take(_ taskID: UUID) {
    guard let meID else { return }
    commit { try $0.takeOpenTask(taskID, actorID: meID) }
  }

  func release(_ taskID: UUID) {
    guard let meID else { return }
    commit { try $0.releaseTask(taskID, actorID: meID) }
  }

  // MARK: Responsibility

  @discardableResult
  func requestTransfer(_ subject: TransferSubject, to receiverID: UUID, message: String?, returnDay: Day?, direct: Bool) -> Bool {
    guard let meID else { return false }
    return commit {
      try $0.requestTransfer(subject, to: receiverID, actorID: meID, message: message, returnDay: returnDay, direct: direct)
    }
  }

  func acceptTransfer(_ requestID: UUID) {
    guard let meID else { return }
    commit { try $0.acceptTransfer(requestID, actorID: meID) }
  }

  func declineTransfer(_ requestID: UUID, reason: String? = nil) {
    guard let meID else { return }
    commit { try $0.declineTransfer(requestID, actorID: meID, reason: reason) }
  }

  func cancelTransfer(_ requestID: UUID) {
    guard let meID else { return }
    commit { try $0.cancelTransfer(requestID, actorID: meID) }
  }

  @discardableResult
  func askForHelp(on taskID: UUID, title: String, helperID: UUID?, day: Day?, message: String?) -> Bool {
    guard let meID else { return false }
    return commit { try $0.askForHelp(on: taskID, title: title, helperID: helperID, day: day, actorID: meID, message: message) }
  }

  // MARK: Family data

  func save(_ member: Member) { commit { $0.save(member) } }
  func save(_ area: Area) { commit { $0.save(area) } }
  func save(_ template: YearTemplate) { commit { $0.save(template) } }
  func save(_ family: Family) { commit { $0.save(family) } }

  func delete(_ member: Member) {
    commit { state in
      for var task in state.tasks where task.responsibleID == member.id || task.subjectMemberID == member.id {
        if task.responsibleID == member.id { task.responsibleID = nil }
        if task.subjectMemberID == member.id { task.subjectMemberID = nil }
        state.save(task)
      }
      state.delete(Member.self, id: member.id)
    }
  }

  func delete(_ template: YearTemplate) { commit { $0.delete(YearTemplate.self, id: template.id) } }
  func delete(_ area: Area) { commit { $0.delete(Area.self, id: area.id) } }

  /// Runs the year clock now, e.g. after templates or birthdays were edited.
  func refreshYearClock() {
    commit { state in
      YearClock().generateTasks(in: &state, today: .today(), actorID: meID)
    }
  }

  /// "Luo nyt": a coming year clock item becomes a task before its usual time.
  func createNow(_ occurrence: YearClock.Occurrence) {
    commit { YearClock.createTask(for: occurrence, in: &$0, today: .today(), actorID: meID) }
  }

  func saveMeeting(kind: MeetingKind, changes: [String]) {
    let participants = state.adults.map(\.id)
    commit { $0.save(MeetingRecord(kind: kind, participantIDs: participants, agreedChanges: changes)) }
  }

  // MARK: Calendars

  func refreshMyEvents() async {
    let start = Calendar.finnish.startOfDay(for: Date()).addingTimeInterval(-7 * 86_400)
    myEvents = await calendars.myEvents(from: start, to: start.addingTimeInterval(70 * 86_400))
    guard let meID, hasFamily, calendars.appleEnabled || calendars.googleEnabled else { return }
    let busy = await calendars.busyRecord(for: meID, shareTitles: DeviceSettings.shareBusyTitles)
    if state.busy.first(where: { $0.id == meID })?.blocks != busy.blocks {
      commit { $0.save(busy) }
    }
  }

  func calendarSettingsChanged() {
    scheduleFollowUp(refreshBusy: true)
  }

  // MARK: Navigation

  func open(taskID: UUID) {
    selectedTab = .today
    openedTaskID = taskID
  }

  func handle(url: URL) {
    guard url.scheme == "tasan", url.host == "task", let id = UUID(uuidString: url.lastPathComponent) else { return }
    open(taskID: id)
  }
}

extension Day {
  /// Sorts undated tasks last.
  static let distant = Day(9999, 12, 31)
}
