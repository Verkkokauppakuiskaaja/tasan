import Foundation
import TasanCore
import os

/*
 * Keeps this phone's calendars in step with the family's tasks.
 *
 * Each phone writes only its own user's responsibilities: when a
 * task moves to the other adult, this phone removes its entries
 * and the other phone adds them after it syncs. The event and its
 * preparation are separate entries ("Synttärit" on Saturday,
 * "Valmistele: Synttärit" on Thursday). The local link table
 * records which calendar event belongs to which task, so only
 * Tasan's own events are ever updated or deleted.
 */
@MainActor
final class CalendarSync {
  struct Link: Codable {
    var appleID: String?
    var googleID: String?
    var fingerprint: String
  }

  let apple = AppleCalendarService()
  let google = GoogleCalendarService()
  private let logger = Logger(subsystem: "fi.tasan.app", category: "calendar")
  private let linksURL: URL
  private var links: [String: Link]
  private var isReconciling = false

  init() {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    linksURL = directory.appendingPathComponent("calendar-links.json")
    links = (try? Data(contentsOf: linksURL)).flatMap { try? JSONDecoder().decode([String: Link].self, from: $0) } ?? [:]
  }

  var appleEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "tasan.calendar.apple") && apple.isAuthorized }
    set { UserDefaults.standard.set(newValue, forKey: "tasan.calendar.apple") }
  }

  var googleEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "tasan.calendar.google") && google.isSignedIn }
    set { UserDefaults.standard.set(newValue, forKey: "tasan.calendar.google") }
  }

  // MARK: Writing

  func reconcile(state: FamilyState, me: UUID?) async {
    guard !isReconciling else { return }
    isReconciling = true
    defer { isReconciling = false }

    let desired = me.map { Self.entries(for: state, me: $0) } ?? [:]

    for (key, entry) in desired {
      var link = links[key] ?? Link(fingerprint: "")
      let changed = link.fingerprint != entry.fingerprint
      do {
        if appleEnabled, changed || link.appleID == nil {
          link.appleID = try apple.upsert(entry, existingID: link.appleID)
        } else if !appleEnabled, let id = link.appleID {
          apple.delete(eventID: id)
          link.appleID = nil
        }
        if googleEnabled, changed || link.googleID == nil {
          link.googleID = try await google.upsert(entry, existingID: link.googleID)
        } else if !googleEnabled, let id = link.googleID, google.isSignedIn {
          await google.delete(eventID: id)
          link.googleID = nil
        }
        link.fingerprint = entry.fingerprint
        links[key] = link
      } catch {
        logger.error("Calendar write failed for \(key): \(error.localizedDescription)")
      }
    }

    // Entries for tasks that are done, deleted or no longer this user's.
    for (key, link) in links where desired[key] == nil {
      if let id = link.appleID { apple.delete(eventID: id) }
      if let id = link.googleID { await google.delete(eventID: id) }
      links[key] = nil
    }
    persist()
  }

  static func entries(for state: FamilyState, me: UUID) -> [String: CalendarEntry] {
    var result: [String: CalendarEntry] = [:]
    let calendar = Calendar.finnish
    for task in state.tasks where task.status == .open && task.responsibleID == me {
      let link = URL(string: "tasan://task/\(task.id.uuidString)")!
      let subject = state.member(task.subjectMemberID)?.name
      let notes = [task.notes, subject.map { "Koskee: \($0)" }].compactMap { $0 }.joined(separator: "\n")

      if let day = task.eventDay {
        let start = task.eventMinutes.map { day.date(minutes: $0, calendar: calendar) } ?? day.date(calendar: calendar)
        let end = task.eventMinutes != nil
          ? start.addingTimeInterval(Double(task.eventDurationMinutes ?? 60) * 60)
          : start
        result["\(task.id)|event"] = CalendarEntry(
          key: "\(task.id)|event",
          title: task.title,
          notes: notes.isEmpty ? nil : notes,
          location: task.location,
          start: start,
          end: end,
          isAllDay: task.eventMinutes == nil,
          alarmOffsetMinutes: task.eventMinutes != nil ? 60 : nil,
          deepLink: link
        )
      }
      if let prep = task.prepDay, prep != task.eventDay {
        let start = prep.date(calendar: calendar)
        result["\(task.id)|prep"] = CalendarEntry(
          key: "\(task.id)|prep",
          title: "Valmistele: \(task.title)",
          notes: notes.isEmpty ? nil : notes,
          location: nil,
          start: start,
          end: start,
          isAllDay: true,
          alarmOffsetMinutes: nil,
          deepLink: link
        )
      }
    }
    return result
  }

  // MARK: Reading

  /// This user's own events from the connected calendars.
  func myEvents(from start: Date, to end: Date) async -> [ExternalEvent] {
    var events = appleEnabled || apple.isAuthorized ? apple.events(from: start, to: end) : []
    if google.isSignedIn {
      do {
        events += try await google.events(from: start, to: end)
      } catch {
        logger.error("Google read failed: \(error.localizedDescription)")
      }
    }
    return events.sorted { $0.start < $1.start }
  }

  /// The busy blocks this phone publishes to the family for the next six weeks.
  func busyRecord(for memberID: UUID, shareTitles: Bool) async -> SharedBusy {
    let start = Calendar.finnish.startOfDay(for: Date())
    let end = start.addingTimeInterval(42 * 86_400)
    let blocks = await myEvents(from: start, to: end)
      .filter(\.isBusy)
      .prefix(400)
      .map { SharedBusy.Block(start: $0.start, end: $0.end, title: shareTitles ? $0.title : nil, isAllDay: $0.isAllDay) }
    return SharedBusy(memberID: memberID, blocks: Array(blocks))
  }

  func forgetLinks() {
    links = [:]
    persist()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(links) {
      try? data.write(to: linksURL, options: .atomic)
    }
  }
}
