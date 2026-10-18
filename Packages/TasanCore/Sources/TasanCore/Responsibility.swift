import Foundation

public enum ResponsibilityError: Error, Equatable, LocalizedError {
  case notFound
  case notAllowed
  case receiverCannotTakeResponsibility
  case alreadyResponsible
  case alreadyPending
  case notPending
  case notReceiver
  case returnDayInPast

  public var errorDescription: String? {
    switch self {
    case .notFound: return CoreText.text("Asiaa ei löytynyt.")
    case .notAllowed: return CoreText.text("Vain vastuuhenkilö tai ylläpitäjä voi siirtää vastuun.")
    case .receiverCannotTakeResponsibility: return CoreText.text("Tämä jäsen ei voi ottaa vastuita.")
    case .alreadyResponsible: return CoreText.text("Hän on jo vastuussa tästä.")
    case .alreadyPending: return CoreText.text("Tälle on jo avoin siirtopyyntö.")
    case .notPending: return CoreText.text("Pyyntöön on jo vastattu.")
    case .notReceiver: return CoreText.text("Vain pyynnön vastaanottaja voi vastata siihen.")
    case .returnDayInPast: return CoreText.text("Paluupäivän pitää olla tulevaisuudessa.")
    }
  }
}

/*
 * Responsibility rules: every change goes through here so the
 * history is always complete and both adults see the same thing.
 */
public extension FamilyState {
  // MARK: Who may do what

  func canTransfer(_ subject: TransferSubject, actorID: UUID) -> Bool {
    guard let actor = member(actorID), actor.role.isAdult else { return false }
    if actor.role.isAdmin { return true }
    return currentResponsible(of: subject) == actorID || currentResponsible(of: subject) == nil
  }

  func currentResponsible(of subject: TransferSubject) -> UUID? {
    switch subject {
    case let .task(id): return task(id)?.responsibleID
    case let .area(id): return area(id)?.ownerID
    }
  }

  func subjectTitle(_ subject: TransferSubject) -> String {
    switch subject {
    case let .task(id): return task(id).map(displayTitle(of:)) ?? CoreText.text("Tehtävä")
    case let .area(id): return area(id)?.displayName ?? CoreText.text("Osa-alue")
    }
  }

  /// Whether `actor` may skip the approval step for this transfer.
  func mayTransferDirectly(actorID: UUID) -> Bool {
    guard let actor = member(actorID), actor.role.isAdmin else { return false }
    return family?.adminDirectTransferEnabled == true
  }

  // MARK: Transfer

  /*
   * "Siirrä vastuu". Creates a pending request, or moves the
   * responsibility at once when `direct` is set and the family
   * lets admins do that. A `returnDay` makes it temporary.
   */
  @discardableResult
  mutating func requestTransfer(
    _ subject: TransferSubject,
    to receiverID: UUID,
    actorID: UUID,
    message: String? = nil,
    returnDay: Day? = nil,
    direct: Bool = false,
    today: Day = .today(),
    now: Date = Date()
  ) throws -> TransferRequest {
    guard exists(subject) else { throw ResponsibilityError.notFound }
    guard canTransfer(subject, actorID: actorID) else { throw ResponsibilityError.notAllowed }
    guard let receiver = member(receiverID), receiver.role.canTakeResponsibility else {
      throw ResponsibilityError.receiverCannotTakeResponsibility
    }
    let from = currentResponsible(of: subject)
    guard from != receiverID else { throw ResponsibilityError.alreadyResponsible }
    guard pendingTransfer(for: subject) == nil else { throw ResponsibilityError.alreadyPending }
    if let returnDay, returnDay <= today { throw ResponsibilityError.returnDayInPast }

    var request = TransferRequest(
      subject: subject,
      fromID: from,
      toID: receiverID,
      requestedByID: actorID,
      message: message?.nilIfBlank,
      returnDay: returnDay,
      createdAt: now
    )

    if direct && mayTransferDirectly(actorID: actorID) || receiverID == actorID {
      // Taking something yourself, or an admin's direct move, needs nobody's approval.
      request.status = .accepted
      request.resolvedAt = now
      save(request, now: now)
      move(subject, from: from, to: receiverID, returnDay: returnDay, actorID: actorID, note: request.message, now: now)
    } else {
      save(request, now: now)
      save(
        HistoryEntry(subject: subject, kind: .transferRequested, actorID: actorID, fromID: from, toID: receiverID, note: request.message, date: now),
        now: now
      )
    }
    return request
  }

  mutating func acceptTransfer(_ requestID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var request = transfers.first(where: { $0.id == requestID }) else { throw ResponsibilityError.notFound }
    guard request.status == .pending else { throw ResponsibilityError.notPending }
    guard request.toID == actorID else { throw ResponsibilityError.notReceiver }
    request.status = .accepted
    request.resolvedAt = now
    save(request, now: now)
    // The responsibility may have changed hands while the request waited; the request still decides.
    move(request.subject, from: currentResponsible(of: request.subject), to: request.toID, returnDay: request.returnDay, actorID: actorID, note: request.message, now: now)
  }

  mutating func declineTransfer(_ requestID: UUID, actorID: UUID, reason: String? = nil, now: Date = Date()) throws {
    guard var request = transfers.first(where: { $0.id == requestID }) else { throw ResponsibilityError.notFound }
    guard request.status == .pending else { throw ResponsibilityError.notPending }
    guard request.toID == actorID else { throw ResponsibilityError.notReceiver }
    request.status = .declined
    request.resolvedAt = now
    save(request, now: now)
    save(
      HistoryEntry(subject: request.subject, kind: .transferDeclined, actorID: actorID, fromID: request.fromID, toID: request.toID, note: reason?.nilIfBlank, date: now),
      now: now
    )
  }

  mutating func cancelTransfer(_ requestID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var request = transfers.first(where: { $0.id == requestID }) else { throw ResponsibilityError.notFound }
    guard request.status == .pending else { throw ResponsibilityError.notPending }
    guard request.requestedByID == actorID || member(actorID)?.role.isAdmin == true else { throw ResponsibilityError.notAllowed }
    request.status = .cancelled
    request.resolvedAt = now
    save(request, now: now)
    save(HistoryEntry(subject: request.subject, kind: .transferCancelled, actorID: actorID, fromID: request.fromID, toID: request.toID, date: now), now: now)
  }

  // MARK: Open tasks

  /// "Ota itselle": anyone who can take responsibility may claim an open task.
  mutating func takeOpenTask(_ taskID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var task = task(taskID) else { throw ResponsibilityError.notFound }
    guard task.responsibleID == nil else { throw ResponsibilityError.notAllowed }
    guard member(actorID)?.role.canTakeResponsibility == true else { throw ResponsibilityError.receiverCannotTakeResponsibility }
    task.responsibleID = actorID
    save(task, now: now)
    save(HistoryEntry(subject: .task(taskID), kind: .taken, actorID: actorID, toID: actorID, date: now), now: now)
  }

  /// "Tee avoimeksi": the responsible person or an admin releases a task for anyone to take.
  mutating func releaseTask(_ taskID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var task = task(taskID) else { throw ResponsibilityError.notFound }
    guard canTransfer(.task(taskID), actorID: actorID) else { throw ResponsibilityError.notAllowed }
    let from = task.responsibleID
    task.responsibleID = nil
    task.temporaryReturn = nil
    save(task, now: now)
    save(HistoryEntry(subject: .task(taskID), kind: .released, actorID: actorID, fromID: from, date: now), now: now)
  }

  // MARK: Ask for help

  /*
   * "Pyydä apua": the responsibility stays, but one sub-task goes
   * to someone else. The sub-task is a normal task (with its own
   * reminder and calendar entry) linked to its parent.
   */
  @discardableResult
  mutating func askForHelp(
    on parentID: UUID,
    title: String,
    helperID: UUID?,
    day: Day?,
    actorID: UUID,
    message: String? = nil,
    now: Date = Date()
  ) throws -> FamilyTask {
    guard let parent = task(parentID) else { throw ResponsibilityError.notFound }
    if let helperID, member(helperID)?.role.canTakeResponsibility != true {
      throw ResponsibilityError.receiverCannotTakeResponsibility
    }
    let subtask = FamilyTask(
      title: title,
      notes: message?.nilIfBlank,
      areaID: parent.areaID,
      responsibleID: nil,
      subjectMemberID: parent.subjectMemberID,
      eventDay: day ?? parent.prepDay ?? parent.eventDay,
      source: .manual,
      parentTaskID: parentID,
      createdAt: now
    )
    save(subtask, now: now)
    save(HistoryEntry(subject: .task(parentID), kind: .helpRequested, actorID: actorID, toID: helperID, note: title, date: now), now: now)
    save(HistoryEntry(subject: .task(subtask.id), kind: .created, actorID: actorID, date: now), now: now)
    if let helperID {
      // The helper approves like any other transfer; until then the sub-task is open.
      try requestTransfer(.task(subtask.id), to: helperID, actorID: actorID, message: message, now: now)
    }
    return subtask
  }

  // MARK: Completion

  mutating func complete(_ taskID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var task = task(taskID) else { throw ResponsibilityError.notFound }
    task.status = .done
    task.completedAt = now
    task.completedByID = actorID
    task.temporaryReturn = nil
    save(task, now: now)
    save(HistoryEntry(subject: .task(taskID), kind: .completed, actorID: actorID, date: now), now: now)
    if let pending = pendingTransfer(for: .task(taskID)) {
      try? cancelTransfer(pending.id, actorID: pending.requestedByID, now: now)
    }
  }

  mutating func reopen(_ taskID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var task = task(taskID) else { throw ResponsibilityError.notFound }
    task.status = .open
    task.completedAt = nil
    task.completedByID = nil
    save(task, now: now)
    save(HistoryEntry(subject: .task(taskID), kind: .reopened, actorID: actorID, date: now), now: now)
  }

  mutating func skip(_ taskID: UUID, actorID: UUID, now: Date = Date()) throws {
    guard var task = task(taskID) else { throw ResponsibilityError.notFound }
    task.status = .skipped
    save(task, now: now)
    save(HistoryEntry(subject: .task(taskID), kind: .completed, actorID: actorID, note: HistoryEntry.skippedNote, date: now), now: now)
  }

  // MARK: Temporary transfers

  /// Moves temporarily transferred responsibilities back once their return day arrives.
  @discardableResult
  mutating func processTemporaryReturns(today: Day, now: Date = Date()) -> [TransferSubject] {
    var returned: [TransferSubject] = []
    for task in tasks where task.status == .open {
      guard let back = task.temporaryReturn, back.day <= today else { continue }
      var updated = task
      let from = updated.responsibleID
      updated.responsibleID = back.memberID
      updated.temporaryReturn = nil
      save(updated, now: now)
      save(
        HistoryEntry(
          id: UUID(deterministic: "\(task.id)|returned|\(back.day)"),
          subject: .task(task.id), kind: .returned, actorID: nil, fromID: from, toID: back.memberID, date: now
        ),
        now: now
      )
      returned.append(.task(task.id))
    }
    for request in transfers where request.status == .accepted {
      guard case let .area(areaID) = request.subject, let day = request.returnDay, day <= today,
        let fromID = request.fromID, var area = area(areaID), area.ownerID == request.toID
      else { continue }
      area.ownerID = fromID
      save(area, now: now)
      var closed = request
      closed.returnDay = nil
      save(closed, now: now)
      save(
        HistoryEntry(
          id: UUID(deterministic: "\(request.id)|returned"),
          subject: .area(areaID), kind: .returned, actorID: nil, fromID: request.toID, toID: fromID, date: now
        ),
        now: now
      )
      returned.append(.area(areaID))
      for var task in tasks where task.areaID == areaID && task.status == .open && task.responsibleID == request.toID {
        task.responsibleID = fromID
        save(task, now: now)
        save(HistoryEntry(subject: .task(task.id), kind: .returned, actorID: nil, fromID: request.toID, toID: fromID, date: now), now: now)
      }
    }
    return returned
  }

  // MARK: Private

  private func exists(_ subject: TransferSubject) -> Bool {
    switch subject {
    case let .task(id): return task(id) != nil
    case let .area(id): return area(id) != nil
    }
  }

  private mutating func move(_ subject: TransferSubject, from: UUID?, to: UUID, returnDay: Day?, actorID: UUID, note: String?, now: Date) {
    switch subject {
    case let .task(id):
      guard var task = task(id) else { return }
      task.responsibleID = to
      task.temporaryReturn = returnDay.flatMap { day in from.map { TemporaryReturn(memberID: $0, day: day) } }
      save(task, now: now)
    case let .area(id):
      guard var area = area(id) else { return }
      area.ownerID = to
      save(area, now: now)
      // Open tasks the previous owner held in this area follow the area.
      for var task in tasks where task.areaID == id && task.status == .open && task.responsibleID == from && from != nil {
        task.responsibleID = to
        save(task, now: now)
        save(HistoryEntry(subject: .task(task.id), kind: .transferred, actorID: actorID, fromID: from, toID: to, note: CoreText.format("Osa-alue %@ siirtyi", area.displayName), date: now), now: now)
      }
    }
    save(HistoryEntry(subject: subject, kind: .transferred, actorID: actorID, fromID: from, toID: to, note: note, date: now), now: now)
  }
}

extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
