import XCTest
@testable import TasanCore

final class FinnishCalendarTests: XCTestCase {
  func testEaster() {
    XCTAssertEqual(FinnishCalendar.easterSunday(2026), Day(2026, 4, 5))
    XCTAssertEqual(FinnishCalendar.easterSunday(2027), Day(2027, 3, 28))
    XCTAssertEqual(FinnishCalendar.easterSunday(2025), Day(2025, 4, 20))
  }

  func testMothersAndFathersDay() {
    XCTAssertEqual(FinnishCalendar.nthWeekday(2, weekday: 7, month: 5, year: 2026), Day(2026, 5, 10))
    XCTAssertEqual(FinnishCalendar.nthWeekday(2, weekday: 7, month: 11, year: 2026), Day(2026, 11, 8))
    XCTAssertEqual(FinnishCalendar.nthWeekday(-1, weekday: 6, month: 10, year: 2026), Day(2026, 10, 31))
  }

  func testIsoWeekAndMidsummer() {
    // Syysloma 2026 begins Monday of week 42.
    XCTAssertEqual(FinnishCalendar.day(isoWeek: 42, weekday: 1, year: 2026), Day(2026, 10, 12))
    XCTAssertEqual(FinnishCalendar.midsummerEve(2026), Day(2026, 6, 19))
    XCTAssertEqual(FinnishCalendar.midsummerEve(2027), Day(2027, 6, 25))
  }

  func testDayMath() {
    XCTAssertEqual(Day(2026, 10, 18).adding(days: 14), Day(2026, 11, 1))
    XCTAssertEqual(Day(2026, 10, 18).isoWeekday(), 7)
    XCTAssertEqual(Day(2026, 3, 1).days(until: Day(2026, 3, 31)), 30)
  }

  func testDeterministicUUID() {
    XCTAssertEqual(UUID(deterministic: "a"), UUID(deterministic: "a"))
    XCTAssertNotEqual(UUID(deterministic: "a"), UUID(deterministic: "b"))
  }
}

final class YearClockTests: XCTestCase {
  var state: FamilyState!
  var mom: Member!
  var dad: Member!
  var liisa: Member!

  override func setUp() {
    mom = Member(name: "Äiti", colorHex: "2560F5", role: .adminAdult)
    dad = Member(name: "Isä", colorHex: "EC602F", role: .adult)
    liisa = Member(name: "Liisa", colorHex: "16A349", role: .child, birthday: Day(2019, 11, 20))
    state = .newFamily(name: "Virtanen", admin: mom)
    state.save(dad)
    state.save(liisa)
  }

  func testOctoberCreatesWhatTheSpecLists() {
    let created = YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    let titles = created.map(\.title)
    XCTAssertTrue(titles.contains("Toppahaalarin ja talvikenkien koko: Liisa"))
    XCTAssertTrue(titles.contains("Heijastimet ja pyörän valot"))
    XCTAssertTrue(titles.contains("Halloween-asu"))
    XCTAssertTrue(titles.contains("Syysloman järjestelyt"))
    // Liisa's birthday 20.11 is within the horizon with a 30-day lead.
    XCTAssertTrue(titles.contains("Synttärijuhlat: Liisa"))
  }

  func testPrepDayIsLeadBeforeEvent() throws {
    YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    let halloween = try XCTUnwrap(state.tasks.first { $0.title == "Halloween-asu" })
    XCTAssertEqual(halloween.eventDay, Day(2026, 10, 31))
    XCTAssertEqual(halloween.prepDay, Day(2026, 10, 17))
  }

  func testGenerationIsIdempotentAndDeterministic() {
    var other = state!
    let first = YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    let again = YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    XCTAssertFalse(first.isEmpty)
    XCTAssertTrue(again.isEmpty)
    // The second phone creates the same ids.
    let fromOther = YearClock().generateTasks(in: &other, today: Day(2026, 10, 1), actorID: dad.id)
    XCTAssertEqual(Set(first.map(\.id)), Set(fromOther.map(\.id)))
  }

  func testSkippedTaskIsNotRecreated() throws {
    YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    let halloween = try XCTUnwrap(state.tasks.first { $0.title == "Halloween-asu" })
    try state.skip(halloween.id, actorID: mom.id)
    let again = YearClock().generateTasks(in: &state, today: Day(2026, 10, 2), actorID: mom.id)
    XCTAssertFalse(again.contains { $0.title == "Halloween-asu" })
  }

  func testTaskGoesToAreaOwnerAndChildSpecificArea() throws {
    var hobbies = try XCTUnwrap(state.areas.first { $0.kind == .holidays })
    hobbies.ownerID = dad.id
    state.save(hobbies)
    state.save(Area(kind: .clothing, name: "Liisan vaatteet", ownerID: dad.id, subjectMemberID: liisa.id))
    YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    XCTAssertEqual(state.tasks.first { $0.title == "Halloween-asu" }?.responsibleID, dad.id)
    XCTAssertEqual(state.tasks.first { $0.title == "Toppahaalarin ja talvikenkien koko: Liisa" }?.responsibleID, dad.id)
    XCTAssertEqual(state.tasks.first { $0.title == "Syysloman järjestelyt" }?.responsibleID, mom.id)
  }

  func testDisabledAreaCreatesNothing() throws {
    var holidays = try XCTUnwrap(state.areas.first { $0.kind == .holidays })
    holidays.enabled = false
    state.save(holidays)
    let created = YearClock().generateTasks(in: &state, today: Day(2026, 10, 1), actorID: mom.id)
    XCTAssertFalse(created.contains { $0.title == "Halloween-asu" })
  }
}

final class ResponsibilityTests: XCTestCase {
  var state: FamilyState!
  var mom: Member!
  var dad: Member!
  var kid: Member!
  var task: FamilyTask!

  override func setUp() {
    mom = Member(name: "Äiti", colorHex: "2560F5", role: .adminAdult)
    dad = Member(name: "Isä", colorHex: "EC602F", role: .adult)
    kid = Member(name: "Eetu", colorHex: "16A349", role: .child)
    state = .newFamily(name: "Virtanen", admin: mom)
    state.save(dad)
    state.save(kid)
    task = FamilyTask(title: "Osta lahja Eetun synttäreille", responsibleID: mom.id, eventDay: Day(2026, 10, 24), prepDay: Day(2026, 10, 22))
    state.save(task)
  }

  func testTransferNeedsApproval() throws {
    let request = try state.requestTransfer(.task(task.id), to: dad.id, actorID: mom.id, message: "Mulla työmatka, voitko ottaa?", today: Day(2026, 10, 18))
    XCTAssertEqual(state.task(task.id)?.responsibleID, mom.id)
    XCTAssertEqual(state.pendingTransfers(to: dad.id).count, 1)
    try state.acceptTransfer(request.id, actorID: dad.id)
    XCTAssertEqual(state.task(task.id)?.responsibleID, dad.id)
    XCTAssertEqual(state.history(for: .task(task.id)).map(\.kind), [.transferRequested, .transferred])
  }

  func testDeclineKeepsResponsibility() throws {
    let request = try state.requestTransfer(.task(task.id), to: dad.id, actorID: mom.id, today: Day(2026, 10, 18))
    XCTAssertThrowsError(try state.acceptTransfer(request.id, actorID: mom.id))
    try state.declineTransfer(request.id, actorID: dad.id, reason: "En ehdi")
    XCTAssertEqual(state.task(task.id)?.responsibleID, mom.id)
    XCTAssertEqual(state.transfers.first?.status, .declined)
  }

  func testChildCannotReceive() {
    XCTAssertThrowsError(try state.requestTransfer(.task(task.id), to: kid.id, actorID: mom.id, today: Day(2026, 10, 18))) {
      XCTAssertEqual($0 as? ResponsibilityError, .receiverCannotTakeResponsibility)
    }
  }

  func testOnlyResponsibleOrAdminMayTransfer() throws {
    var dadsTask = FamilyTask(title: "Kuljetus", responsibleID: mom.id)
    state.save(dadsTask)
    XCTAssertThrowsError(try state.requestTransfer(.task(dadsTask.id), to: dad.id, actorID: dad.id, today: Day(2026, 10, 18)))
    dadsTask.responsibleID = dad.id
    state.save(dadsTask)
    // The admin may still move someone else's task.
    XCTAssertNoThrow(try state.requestTransfer(.task(dadsTask.id), to: mom.id, actorID: mom.id, today: Day(2026, 10, 18)))
  }

  func testDirectTransferOnlyWhenSettingIsOn() throws {
    let first = try state.requestTransfer(.task(task.id), to: dad.id, actorID: mom.id, direct: true, today: Day(2026, 10, 18))
    XCTAssertEqual(first.status, .pending)
    try state.cancelTransfer(first.id, actorID: mom.id)

    var family = try XCTUnwrap(state.family)
    family.adminDirectTransferEnabled = true
    state.save(family)
    let second = try state.requestTransfer(.task(task.id), to: dad.id, actorID: mom.id, direct: true, today: Day(2026, 10, 18))
    XCTAssertEqual(second.status, .accepted)
    XCTAssertEqual(state.task(task.id)?.responsibleID, dad.id)
  }

  func testTemporaryTransferReturns() throws {
    let request = try state.requestTransfer(.task(task.id), to: dad.id, actorID: mom.id, returnDay: Day(2026, 10, 21), today: Day(2026, 10, 18))
    try state.acceptTransfer(request.id, actorID: dad.id)
    XCTAssertEqual(state.task(task.id)?.responsibleID, dad.id)
    XCTAssertTrue(state.processTemporaryReturns(today: Day(2026, 10, 20)).isEmpty)
    XCTAssertEqual(state.processTemporaryReturns(today: Day(2026, 10, 21)), [.task(task.id)])
    XCTAssertEqual(state.task(task.id)?.responsibleID, mom.id)
  }

  func testAreaTransferMovesOpenTasksAndNewOnes() throws {
    let area = try XCTUnwrap(state.areas.first { $0.kind == .parties })
    var partyTask = task!
    partyTask.areaID = area.id
    state.save(partyTask)
    let request = try state.requestTransfer(.area(area.id), to: dad.id, actorID: mom.id, today: Day(2026, 10, 18))
    try state.acceptTransfer(request.id, actorID: dad.id)
    XCTAssertEqual(state.area(area.id)?.ownerID, dad.id)
    XCTAssertEqual(state.task(task.id)?.responsibleID, dad.id)
  }

  func testOpenTaskCanBeTaken() throws {
    let open = FamilyTask(title: "Retkieväät")
    state.save(open)
    XCTAssertTrue(open.isOpenForTaking)
    try state.takeOpenTask(open.id, actorID: dad.id)
    XCTAssertEqual(state.task(open.id)?.responsibleID, dad.id)
    XCTAssertThrowsError(try state.takeOpenTask(open.id, actorID: mom.id))
  }

  func testAskForHelpKeepsParentResponsibility() throws {
    let sub = try state.askForHelp(on: task.id, title: "Hae lahja postista", helperID: dad.id, day: Day(2026, 10, 21), actorID: mom.id)
    XCTAssertEqual(state.task(task.id)?.responsibleID, mom.id)
    XCTAssertEqual(state.subtasks(of: task.id).map(\.id), [sub.id])
    XCTAssertEqual(state.pendingTransfers(to: dad.id).count, 1)
  }

  func testCompleteCancelsPendingTransfer() throws {
    _ = try state.requestTransfer(.task(task.id), to: dad.id, actorID: mom.id, today: Day(2026, 10, 18))
    try state.complete(task.id, actorID: mom.id)
    XCTAssertEqual(state.transfers.first?.status, .cancelled)
    XCTAssertEqual(state.task(task.id)?.status, .done)
  }
}

final class LoadAndMeetingTests: XCTestCase {
  func testLoadAndWeeklyAgenda() throws {
    let mom = Member(name: "Äiti", colorHex: "2560F5", role: .adminAdult)
    let dad = Member(name: "Isä", colorHex: "EC602F", role: .adult)
    var state = FamilyState.newFamily(name: "V", admin: mom)
    state.save(dad)
    let today = Day(2026, 10, 18)
    state.save(FamilyTask(title: "A", responsibleID: mom.id, eventDay: today.adding(days: 2)))
    state.save(FamilyTask(title: "B", responsibleID: mom.id, eventDay: today.adding(days: 20)))
    state.save(FamilyTask(title: "C", responsibleID: dad.id, eventDay: today.adding(days: 3), eventMinutes: 17 * 60))
    state.save(FamilyTask(title: "D", eventDay: today.adding(days: 4)))

    let load = LoadSummary.make(from: state, today: today)
    XCTAssertEqual(load.rows.first { $0.memberID == mom.id }?.openTasks, 2)
    XCTAssertEqual(load.openForTaking, 1)
    XCTAssertEqual(load.share(of: dad.id), 1.0 / 3.0, accuracy: 0.001)

    let start = today.adding(days: 3).date(minutes: 16 * 60 + 30)
    let busy = [BusyInterval(memberID: dad.id, start: start, end: start.addingTimeInterval(3600), title: "Palaveri")]
    let agenda = MeetingAgenda.make(.weekly, state: state, today: today, busy: busy)
    XCTAssertEqual(agenda.upcoming.map(\.title), ["A", "C", "D"])
    XCTAssertEqual(agenda.openForTaking.map(\.title), ["D"])
    XCTAssertEqual(agenda.overlaps.first?.suggestedMemberID, mom.id)
  }

  func testMonthlyAgendaShowsComingYearClockItems() {
    let mom = Member(name: "Äiti", colorHex: "2560F5", role: .adminAdult)
    let state = FamilyState.newFamily(name: "V", admin: mom)
    let agenda = MeetingAgenda.make(.monthly, state: state, today: Day(2026, 10, 25))
    XCTAssertTrue(agenda.comingFromYearClock.contains { $0.template.title == "Isänpäivä" })
    XCTAssertTrue(agenda.comingFromYearClock.contains { $0.template.title == "Joulukalenterit" })
  }

  func testMeetingChangeLog() throws {
    let mom = Member(name: "Äiti", colorHex: "2560F5", role: .adminAdult)
    let dad = Member(name: "Isä", colorHex: "EC602F", role: .adult)
    var state = FamilyState.newFamily(name: "V", admin: mom)
    state.save(dad)
    let open = FamilyTask(title: "Retkieväät")
    state.save(open)
    let log = MeetingChangeLog(startedAt: Date().addingTimeInterval(-1))
    try state.takeOpenTask(open.id, actorID: dad.id)
    XCTAssertEqual(log.changes(in: state), ["Retkieväät: Isä otti hoitaakseen"])
  }
}

final class SyncStateTests: XCTestCase {
  func testRoundTripAndLastWriterWins() throws {
    let mom = Member(name: "Äiti", colorHex: "2560F5", role: .adminAdult)
    var phoneA = FamilyState.newFamily(name: "V", admin: mom)
    var phoneB = FamilyState()
    for ref in phoneA.allRefs {
      let data = try XCTUnwrap(phoneA.encodedRecord(ref))
      XCTAssertTrue(try phoneB.applyRemotePayload(type: ref.type, data: data))
    }
    XCTAssertEqual(phoneB.templates.count, phoneA.templates.count)
    XCTAssertEqual(phoneB.family?.id, phoneA.family?.id)

    let task = FamilyTask(title: "Uusi")
    phoneA.save(task, now: Date(timeIntervalSince1970: 100))
    var newer = task
    newer.title = "Uudempi"
    phoneB.save(newer, now: Date(timeIntervalSince1970: 200))
    let ref = RecordRef(type: FamilyTask.recordType, id: task.id)
    XCTAssertFalse(try phoneB.applyRemotePayload(type: ref.type, data: XCTUnwrap(phoneA.encodedRecord(ref))))
    XCTAssertEqual(phoneB.task(task.id)?.title, "Uudempi")
    XCTAssertEqual(RecordRef(recordName: ref.recordName), ref)
  }
}
