import Foundation

/*
 * A calendar day without a time zone. Family tasks are about
 * days ("synttärit lauantaina"), and storing them as Date would
 * shift them by a day whenever two phones disagree on the zone.
 * The Finnish calendar (Europe/Helsinki, Monday first) is the
 * reference for weekday and week-number math.
 */
public struct Day: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
  public var year: Int
  public var month: Int
  public var day: Int

  public init(_ year: Int, _ month: Int, _ day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  public init(date: Date, calendar: Calendar = .finnish) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(parts.year!, parts.month!, parts.day!)
  }

  public static func today(calendar: Calendar = .finnish) -> Day {
    Day(date: Date(), calendar: calendar)
  }

  /// Midnight at the start of the day in the given calendar.
  public func date(calendar: Calendar = .finnish) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  /// A moment during the day, `minutes` after midnight.
  public func date(minutes: Int, calendar: Calendar = .finnish) -> Date {
    calendar.date(
      from: DateComponents(
        year: year, month: month, day: day,
        hour: minutes / 60, minute: minutes % 60
      )
    )!
  }

  public func adding(days: Int, calendar: Calendar = .finnish) -> Day {
    Day(date: calendar.date(byAdding: .day, value: days, to: date(calendar: calendar))!, calendar: calendar)
  }

  public func days(until other: Day, calendar: Calendar = .finnish) -> Int {
    calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day!
  }

  /// ISO weekday: 1 = Monday ... 7 = Sunday.
  public func isoWeekday(calendar: Calendar = .finnish) -> Int {
    let weekday = calendar.component(.weekday, from: date(calendar: calendar))
    return weekday == 1 ? 7 : weekday - 1
  }

  public func isoWeek(calendar: Calendar = .finnish) -> Int {
    var iso = Calendar(identifier: .iso8601)
    iso.timeZone = calendar.timeZone
    return iso.component(.weekOfYear, from: date(calendar: calendar))
  }

  public static func < (lhs: Day, rhs: Day) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  public var description: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  /// "18.10.2026", the way Finns write dates.
  public var finnishString: String {
    "\(day).\(month).\(year)"
  }

  public var finnishShortString: String {
    "\(day).\(month)."
  }

  public static func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  public static func daysInMonth(_ month: Int, year: Int) -> Int {
    switch month {
    case 2: return isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }
}

extension Calendar {
  /// Gregorian, Monday-first, Helsinki time: the calendar the year clock runs on.
  public static var finnish: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current
    calendar.locale = Locale(identifier: "fi_FI")
    return calendar
  }
}
