import Foundation

/*
 * When a year clock template's event falls in a given year.
 * Rules are data so families can edit them and they sync as JSON.
 */
public enum YearRule: Codable, Equatable, Sendable {
  /// Same date every year, e.g. vappu 1.5.
  case fixed(month: Int, day: Int)
  /// The nth ISO weekday of a month (n = -1 for the last), e.g. äitienpäivä = 2nd Sunday of May.
  case nthWeekday(month: Int, weekday: Int, n: Int)
  /// Days relative to Easter Sunday, e.g. pitkäperjantai = -2.
  case easter(offset: Int)
  /// An ISO weekday in an ISO week, e.g. syysloma Monday of week 42.
  case isoWeek(week: Int, weekday: Int)
  /// Monday of the family's school winter holiday week (hiihtoloma).
  case winterHoliday
  /// Juhannusaatto, the Friday between 19 and 25 June.
  case midsummerEve
  /// Each child's birthday, plus an offset in days.
  case birthday(offset: Int)

  /// Event days in `year` for this rule. Birthday rules need the members.
  public func days(in year: Int, family: Family, children: [Member]) -> [(day: Day, memberID: UUID?)] {
    switch self {
    case let .fixed(month, day):
      let clamped = min(day, Day.daysInMonth(month, year: year))
      return [(Day(year, month, clamped), nil)]

    case let .nthWeekday(month, weekday, n):
      return FinnishCalendar.nthWeekday(n, weekday: weekday, month: month, year: year).map { [($0, nil)] } ?? []

    case let .easter(offset):
      return [(FinnishCalendar.easterSunday(year).adding(days: offset), nil)]

    case let .isoWeek(week, weekday):
      return FinnishCalendar.day(isoWeek: week, weekday: weekday, year: year).map { [($0, nil)] } ?? []

    case .winterHoliday:
      return FinnishCalendar.day(isoWeek: family.winterHolidayWeek, weekday: 1, year: year).map { [($0, nil)] } ?? []

    case .midsummerEve:
      return [(FinnishCalendar.midsummerEve(year), nil)]

    case let .birthday(offset):
      return children.compactMap { child in
        guard let birthday = child.birthday else { return nil }
        let clamped = min(birthday.day, Day.daysInMonth(birthday.month, year: year))
        return (Day(year, birthday.month, clamped).adding(days: offset), child.id)
      }
    }
  }

  public var isPerMember: Bool {
    if case .birthday = self { return true }
    return false
  }
}

public enum FinnishCalendar {
  /// Gregorian Easter Sunday (anonymous Gregorian algorithm).
  public static func easterSunday(_ year: Int) -> Day {
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let day = ((h + l - 7 * m + 114) % 31) + 1
    return Day(year, month, day)
  }

  public static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int) -> Day? {
    if n == -1 {
      var day = Day(year, month, Day.daysInMonth(month, year: year))
      while day.isoWeekday() != weekday { day = day.adding(days: -1) }
      return day
    }
    guard n >= 1 else { return nil }
    var day = Day(year, month, 1)
    while day.isoWeekday() != weekday { day = day.adding(days: 1) }
    let result = day.adding(days: 7 * (n - 1))
    return result.month == month ? result : nil
  }

  public static func day(isoWeek week: Int, weekday: Int, year: Int) -> Day? {
    // ISO week 1 is the week containing 4 January.
    let jan4 = Day(year, 1, 4)
    let week1Monday = jan4.adding(days: -(jan4.isoWeekday() - 1))
    let result = week1Monday.adding(days: (week - 1) * 7 + (weekday - 1))
    return result.isoWeek() == week ? result : nil
  }

  public static func midsummerEve(_ year: Int) -> Day {
    var day = Day(year, 6, 19)
    while day.isoWeekday() != 5 { day = day.adding(days: 1) }
    return day
  }
}
