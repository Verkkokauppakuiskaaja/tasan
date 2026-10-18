import EventKit
import Foundation
import UIKit

/*
 * Apple Calendar through EventKit. Tasan! writes only into its own
 * "Tasan!" calendar, so the user's own events are never touched,
 * and reads all of the user's calendars for the family calendar
 * view and overlap checks (full access, iOS 17).
 */
final class AppleCalendarService {
  static let calendarTitle = "Tasan!"
  private let store = EKEventStore()
  private let calendarIDKey = "tasan.apple.calendarID"

  var isAuthorized: Bool {
    EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }

  func requestAccess() async -> Bool {
    (try? await store.requestFullAccessToEvents()) ?? false
  }

  // MARK: Tasan calendar

  /// Finds or creates the app's own calendar, preferring iCloud so it is on all the user's devices.
  func tasanCalendar() throws -> EKCalendar {
    if let id = UserDefaults.standard.string(forKey: calendarIDKey), let calendar = store.calendar(withIdentifier: id) {
      return calendar
    }
    if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
      UserDefaults.standard.set(existing.calendarIdentifier, forKey: calendarIDKey)
      return existing
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = Self.calendarTitle
    calendar.cgColor = UIColor(red: 0x25 / 255, green: 0x60 / 255, blue: 0xF5 / 255, alpha: 1).cgColor
    let sources = store.sources
    calendar.source =
      sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
      ?? store.defaultCalendarForNewEvents?.source
      ?? sources.first { $0.sourceType == .local }
    try store.saveCalendar(calendar, commit: true)
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDKey)
    return calendar
  }

  // MARK: Writing

  /// Creates or updates an event. Returns its identifier.
  func upsert(_ entry: CalendarEntry, existingID: String?) throws -> String {
    let calendar = try tasanCalendar()
    let event = existingID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
    event.calendar = calendar
    event.title = entry.title
    event.notes = entry.notes
    event.location = entry.location
    event.isAllDay = entry.isAllDay
    event.startDate = entry.start
    event.endDate = entry.isAllDay ? entry.start : entry.end
    // The URL marks the event as ours and opens the task from Calendar.
    event.url = entry.deepLink
    event.alarms = entry.alarmOffsetMinutes.map { [EKAlarm(relativeOffset: TimeInterval(-$0 * 60))] }
    try store.save(event, span: .thisEvent, commit: true)
    return event.eventIdentifier
  }

  func delete(eventID: String) {
    guard let event = store.event(withIdentifier: eventID), event.calendar.title == Self.calendarTitle else { return }
    try? store.remove(event, span: .thisEvent, commit: true)
  }

  // MARK: Reading

  /// The user's own events (not Tasan's) in a range.
  func events(from start: Date, to end: Date) -> [ExternalEvent] {
    guard isAuthorized else { return [] }
    let calendars = store.calendars(for: .event).filter { $0.title != Self.calendarTitle }
    guard !calendars.isEmpty else { return [] }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    return store.events(matching: predicate).map {
      ExternalEvent(
        id: "apple:\($0.eventIdentifier ?? UUID().uuidString)",
        title: $0.title ?? "",
        start: $0.startDate,
        end: $0.endDate,
        isAllDay: $0.isAllDay,
        isBusy: $0.availability != .free,
        source: .apple
      )
    }
  }
}

/// What Tasan! writes into a calendar for one task entry.
struct CalendarEntry: Equatable {
  /// "<taskID>|event" or "<taskID>|prep".
  var key: String
  var title: String
  var notes: String?
  var location: String?
  var start: Date
  var end: Date
  var isAllDay: Bool
  var alarmOffsetMinutes: Int?
  var deepLink: URL

  /// Changes when anything visible changes, so unchanged entries are not rewritten.
  var fingerprint: String {
    [title, notes ?? "", location ?? "", "\(start.timeIntervalSince1970)", "\(end.timeIntervalSince1970)", "\(isAllDay)", "\(alarmOffsetMinutes ?? -1)"]
      .joined(separator: "|")
  }
}

/// An event from someone's own calendar, read for the family view.
struct ExternalEvent: Identifiable, Equatable {
  enum Source: String { case apple, google }

  var id: String
  var title: String
  var start: Date
  var end: Date
  var isAllDay: Bool
  var isBusy: Bool
  var source: Source
}
