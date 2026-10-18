import Foundation
import TasanCore
import UIKit
import UserNotifications

/*
 * Two kinds of notifications, both posted on the phone of the
 * person they concern:
 *
 * - Reminders for this user's own tasks, scheduled locally. When a
 *   task moves to the other adult, this phone drops the reminder
 *   and theirs schedules it after syncing.
 * - Responsibility requests and answers. CloudKit wakes the phone
 *   with a silent push when the shared zone changes; the app then
 *   notices a new request addressed to this user and shows it with
 *   Accept / Decline buttons.
 */
@MainActor
final class NotificationService: NSObject {
  static let transferCategory = "TRANSFER_REQUEST"
  static let acceptAction = "ACCEPT"
  static let declineAction = "DECLINE"
  private static let reminderPrefix = "reminder."

  private let center = UNUserNotificationCenter.current()

  /// Set by the app model to act on notification buttons.
  var onTransferAction: ((UUID, Bool) -> Void)?
  var onOpenTask: ((UUID) -> Void)?
  var onOpenMeeting: (() -> Void)?

  override init() {
    super.init()
    center.delegate = self
    let accept = UNNotificationAction(identifier: Self.acceptAction, title: "Hyväksy", options: [.authenticationRequired])
    let decline = UNNotificationAction(identifier: Self.declineAction, title: "Kieltäydy", options: [.destructive])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: Self.transferCategory, actions: [accept, decline], intentIdentifiers: [])
    ])
  }

  func requestAuthorization() async -> Bool {
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    UIApplication.shared.registerForRemoteNotifications()
    return granted
  }

  // MARK: Reminders

  /// Replaces all task reminders with the current ones. iOS keeps at most 64, so the nearest win.
  func rescheduleReminders(state: FamilyState, me: UUID?) async {
    let pending = await center.pendingNotificationRequests()
    center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) })
    guard let me else { return }

    let now = Date()
    let upcoming = state.tasks
      .filter { $0.status == .open && $0.responsibleID == me }
      .compactMap { task -> (FamilyTask, Date)? in
        guard let date = task.reminderDate(), date > now else { return nil }
        return (task, date)
      }
      .sorted { $0.1 < $1.1 }
      .prefix(50)

    for (task, date) in upcoming {
      let content = UNMutableNotificationContent()
      content.title = task.title
      content.body = Self.reminderBody(task)
      content.sound = .default
      content.userInfo = ["taskID": task.id.uuidString]
      let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      let request = UNNotificationRequest(
        identifier: Self.reminderPrefix + task.id.uuidString,
        content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
      )
      try? await center.add(request)
    }
  }

  private static func reminderBody(_ task: FamilyTask) -> String {
    guard let event = task.eventDay else { return "Muistutus Tasan!-sovelluksesta" }
    if let prep = task.prepDay, prep != event {
      return "Valmistelu tänään, tapahtuma \(event.finnishShortString)"
    }
    return "Tapahtuma \(event.finnishShortString)"
  }

  // MARK: Family meeting

  /// Weekly reminder at the chosen time, monthly on the last Sunday of the month.
  func scheduleMeetingReminders(family: Family?) async {
    center.removePendingNotificationRequests(withIdentifiers: ["meeting.weekly", "meeting.monthly"])
    guard let family else { return }

    if family.weeklyMeeting.enabled {
      let content = UNMutableNotificationContent()
      content.title = "Viikkopalaveri"
      content.body = "Käykää yhdessä läpi seuraavat 7 päivää. Noin 15 minuuttia."
      content.sound = .default
      content.userInfo = ["meeting": "weekly"]
      var parts = DateComponents()
      // DateComponents weekday: 1 = Sunday.
      parts.weekday = family.weeklyMeeting.weekday == 7 ? 1 : family.weeklyMeeting.weekday + 1
      parts.hour = family.weeklyMeeting.minutes / 60
      parts.minute = family.weeklyMeeting.minutes % 60
      try? await center.add(
        UNNotificationRequest(identifier: "meeting.weekly", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true))
      )
    }

    if family.monthlyMeetingEnabled {
      let today = Day.today()
      var target = FinnishCalendar.nthWeekday(-1, weekday: 7, month: today.month, year: today.year) ?? today
      if target < today {
        let next = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
        target = FinnishCalendar.nthWeekday(-1, weekday: 7, month: next.1, year: next.0) ?? today
      }
      let content = UNMutableNotificationContent()
      content.title = "Kuukausipalaveri"
      content.body = "Isommat hankinnat, juhlat, lomat ja vuosikellon tulevat asiat. Noin 30 minuuttia."
      content.sound = .default
      content.userInfo = ["meeting": "monthly"]
      let date = target.date(minutes: family.weeklyMeeting.minutes)
      let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      try? await center.add(
        UNNotificationRequest(identifier: "meeting.monthly", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
      )
    }
  }

  // MARK: Requests

  /// Announces new requests to this user and answers to this user's requests, once each.
  func announceTransfers(state: FamilyState, me: UUID?) {
    guard let me else { return }
    var notified = DeviceSettings.notifiedTransferIDs

    for request in state.transfers {
      let key = "\(request.id.uuidString).\(request.status.rawValue)"
      guard !notified.contains(key) else { continue }
      notified.insert(key)
      // Our own actions and anything older than a day are not news.
      guard request.modifiedAt > Date().addingTimeInterval(-86_400) else { continue }

      let title = state.subjectTitle(request.subject)
      let from = state.member(request.requestedByID)?.name ?? "Perheenjäsen"
      let to = state.member(request.toID)?.name ?? "Perheenjäsen"
      let content = UNMutableNotificationContent()
      content.sound = .default
      content.userInfo = ["transferID": request.id.uuidString]

      switch request.status {
      case .pending where request.toID == me && request.requestedByID != me:
        content.title = "\(from) pyytää: \(title)"
        content.body = request.message ?? (request.returnDay.map { "Väliaikainen siirto \($0.finnishShortString) asti" } ?? "Voitko ottaa tämän vastuun?")
        content.categoryIdentifier = Self.transferCategory
      case .accepted where request.requestedByID == me && request.toID != me:
        content.title = "\(to) otti vastuun"
        content.body = title
      case .declined where request.requestedByID == me:
        content.title = "\(to) ei voi ottaa"
        content.body = "\(title) pysyy ennallaan."
      default:
        continue
      }
      center.add(UNNotificationRequest(identifier: "transfer.\(key)", content: content, trigger: nil))
    }
    DeviceSettings.notifiedTransferIDs = notified
  }

  /// Marks everything currently known as already announced, e.g. right after joining a family.
  func markAllTransfersSeen(state: FamilyState) {
    DeviceSettings.notifiedTransferIDs = Set(state.transfers.map { "\($0.id.uuidString).\($0.status.rawValue)" })
  }

  func updateBadge(count: Int) {
    center.setBadgeCount(count)
  }
}

extension NotificationService: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let info = response.notification.request.content.userInfo
    let action = response.actionIdentifier
    let transferID = (info["transferID"] as? String).flatMap(UUID.init(uuidString:))
    let taskID = (info["taskID"] as? String).flatMap(UUID.init(uuidString:))
    let isMeeting = info["meeting"] != nil
    await MainActor.run {
      if let transferID, action == Self.acceptAction || action == Self.declineAction {
        onTransferAction?(transferID, action == Self.acceptAction)
      } else if let taskID {
        onOpenTask?(taskID)
      } else if isMeeting {
        onOpenMeeting?()
      }
    }
  }
}
