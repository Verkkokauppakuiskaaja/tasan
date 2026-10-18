import Foundation
import TasanCore

/*
 * The app speaks Finnish, English or Swedish, following the
 * phone's language. Texts live in String Catalogs: Localizable for
 * the app, Core for the shared rules (TasanCore keeps its Finnish
 * source strings, and stored family data stays Finnish so two
 * phones in different languages agree). Dates follow the phone's
 * region and language instead of a fixed Finnish format.
 */
enum AppLanguage {
  /// Points the core rules' text at Core.xcstrings. Called once at launch.
  static func install() {
    CoreText.lookup = { Bundle.main.localizedString(forKey: $0, value: $0, table: "Core") }
  }

  /// The language the interface is shown in: "fi", "en" or "sv".
  static var current: String {
    Bundle.main.preferredLocalizations.first ?? "fi"
  }
}

enum DateText {
  private static func formatter(_ template: String) -> DateFormatter {
    // The year clock's Gregorian calendar and Helsinki days, with names and order from the phone's language.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Calendar.finnish.timeZone
    calendar.locale = .current
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = .current
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter
  }

  /// "24.10.", "10/24" or "24/10".
  static func dayMonth(_ day: Day) -> String {
    formatter("dM").string(from: day.date())
  }

  /// "la 24.10." in Finnish, "Sat, 10/24" in English; the year is added when it is not this year.
  static func weekdayDayMonth(_ day: Day, today: Day = .today()) -> String {
    formatter(day.year == today.year ? "EEEdM" : "EEEdMyyyy").string(from: day.date())
  }

  /// "1. toukokuuta", "May 1", "1 maj".
  static func dayOfMonth(_ day: Int, month: Int) -> String {
    // A leap year, so 29 February has a date.
    formatter("dMMMM").string(from: Day(2000, month, min(day, Day.daysInMonth(month, year: 2000))).date())
  }

  /// "9.05", "9:05 AM", "09:05".
  static func time(minutes: Int) -> String {
    Day.today().date(minutes: minutes).formatted(date: .omitted, time: .shortened)
  }

  static func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  /// Month name as a heading, e.g. "Tammikuu", "January", "Januari". `month` is 1...12.
  static func monthName(_ month: Int) -> String {
    let symbols = formatter("MMMM").standaloneMonthSymbols ?? []
    return symbols.indices.contains(month - 1) ? symbols[month - 1].capitalized(with: .current) : "\(month)"
  }

  /// Weekday name in running text, e.g. "maanantai", "Monday", "måndag". `isoWeekday` is 1 (Monday) ... 7 (Sunday).
  static func weekdayName(_ isoWeekday: Int) -> String {
    let symbols = formatter("EEEE").standaloneWeekdaySymbols ?? []
    return symbols.isEmpty ? "\(isoWeekday)" : symbols[isoWeekday % 7]
  }

  /// "ma", "Mon", "mån".
  static func weekdayShortName(_ isoWeekday: Int) -> String {
    let symbols = formatter("EEE").shortStandaloneWeekdaySymbols ?? []
    return symbols.isEmpty ? "\(isoWeekday)" : symbols[isoWeekday % 7]
  }

  /// "2.", "2nd", "2:a".
  static func ordinal(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)."
  }
}

extension YearRule {
  /// Short description for the year clock editor, in the current language.
  var localizedDescription: String {
    switch self {
    case let .fixed(month, day):
      return String(localized: "\(DateText.dayOfMonth(day, month: month)) joka vuosi")
    case let .nthWeekday(month, weekday, n):
      let ordinal = n == -1 ? String(localized: "viimeinen") : DateText.ordinal(n)
      return String(localized: "\(DateText.monthName(month)): \(ordinal) \(DateText.weekdayName(weekday))", comment: "Year clock rule, e.g. May: 2nd Sunday")
    case let .easter(offset):
      if offset == 0 { return String(localized: "Pääsiäispäivä") }
      return offset < 0 ? String(localized: "\(-offset) pv ennen pääsiäistä") : String(localized: "\(offset) pv pääsiäisen jälkeen")
    case let .isoWeek(week, weekday):
      return String(localized: "Viikko \(week), \(DateText.weekdayName(weekday))")
    case .winterHoliday:
      return String(localized: "Hiihtoloman alku")
    case .midsummerEve:
      return String(localized: "Juhannusaatto")
    case let .birthday(offset):
      if offset == 0 { return String(localized: "Lapsen syntymäpäivä") }
      return offset < 0 ? String(localized: "\(-offset) pv ennen syntymäpäivää") : String(localized: "\(offset) pv syntymäpäivän jälkeen")
    }
  }
}
