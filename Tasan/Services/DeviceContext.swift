import Foundation

struct DeviceContext: Codable, Equatable {
  let locale: String
  let timeZoneIdentifier: String
  let uses24HourClock: Bool
  let calendarIdentifier: String
  let preferredLanguage: String
  let measurementSystem: String
  let referenceDate: String
  /// The language the app is shown in ("fi", "en" or "sv"); the service writes the preparation hint in it.
  let appLanguage: String

  static var current: DeviceContext {
    let locale = Locale.current
    let preferredLanguage =
      Locale.preferredLanguages.first
      ?? locale.identifier

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
      .withInternetDateTime,
      .withFractionalSeconds
    ]

    return DeviceContext(
      locale: locale.identifier,
      timeZoneIdentifier:
        TimeZone.current.identifier,
      uses24HourClock:
        Self.detects24HourClock(
          locale: locale
        ),
      calendarIdentifier:
        String(
          describing:
            Calendar.current.identifier
        ),
      preferredLanguage:
        preferredLanguage,
      measurementSystem:
        locale.measurementSystem == .metric
        ? "metric"
        : "us",
      referenceDate:
        formatter.string(
          from: Date()
        ),
      appLanguage:
        AppLanguage.current
    )
  }

  var preferredOCRLanguages: [String] {
    var candidates = [
      preferredLanguage,
      locale,
      "en-US",
      "fi-FI",
      "sv-SE"
    ]

    var seen = Set<String>()

    candidates = candidates.filter {
      value in

      let normalized =
        value.trimmingCharacters(
          in: .whitespacesAndNewlines
        )

      guard
        !normalized.isEmpty,
        !seen.contains(normalized)
      else {
        return false
      }

      seen.insert(normalized)
      return true
    }

    return candidates
  }

  private static func detects24HourClock(
    locale: Locale
  ) -> Bool {
    let format =
      DateFormatter.dateFormat(
        fromTemplate: "j",
        options: 0,
        locale: locale
      ) ?? ""

    return !format.contains("a")
  }
}