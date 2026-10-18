import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/*
 * Google Calendar over its REST API. Each adult signs in with
 * their own Google account (OAuth 2 with PKCE, no client secret).
 * Tasan! creates its own "Tasan!" calendar in that account and
 * writes only there; the user's other calendars are only read.
 *
 * Setup: create an iOS OAuth client in Google Cloud Console for
 * the bundle id, enable the Calendar API, and put the client id
 * in Info.plist as GOOGLE_CLIENT_ID (Config/Secrets.xcconfig).
 */
@MainActor
final class GoogleCalendarService: NSObject {
  enum GoogleError: LocalizedError {
    case notConfigured
    case notSignedIn
    case cancelled
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
      switch self {
      case .notConfigured: return String(localized: "Google-kalenteria ei ole vielä määritetty tähän versioon (GOOGLE_CLIENT_ID puuttuu).")
      case .notSignedIn: return String(localized: "Kirjaudu ensin Google-tilillesi.")
      case .cancelled: return String(localized: "Kirjautuminen peruttiin.")
      case let .http(code, message): return String(localized: "Google vastasi virheellä \(code): \(message)")
      case .invalidResponse: return String(localized: "Google palautti odottamattoman vastauksen.")
      }
    }
  }

  /// Own secondary calendars, plus reading the user's events for overlaps and the family view.
  private static let scopes = [
    "https://www.googleapis.com/auth/calendar.app.created",
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
  ]
  private static let api = URL(string: "https://www.googleapis.com/calendar/v3")!
  private static let calendarIDKey = "tasan.google.calendarID"

  private var tokens: Tokens? = Keychain.read(Tokens.self, account: "google.tokens")
  private var authSession: ASWebAuthenticationSession?

  private var clientID: String? {
    (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String)
      .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 }
  }

  /// com.googleusercontent.apps.<id> — Google's iOS redirect scheme.
  private var redirectScheme: String? {
    clientID.map { $0.components(separatedBy: ".").reversed().joined(separator: ".") }
  }

  var isConfigured: Bool { clientID != nil }
  var isSignedIn: Bool { tokens != nil }
  var accountEmail: String? { tokens?.email }

  // MARK: Sign in

  func signIn() async throws {
    guard let clientID, let redirectScheme else { throw GoogleError.notConfigured }
    let verifier = Self.randomURLSafeString(length: 64)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    let redirectURI = "\(redirectScheme):/oauth2redirect"

    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: (Self.scopes + ["email"]).joined(separator: " ")),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "access_type", value: "offline"),
      URLQueryItem(name: "prompt", value: "consent"),
    ]

    let callback: URL = try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: redirectScheme) { url, error in
        if let url {
          continuation.resume(returning: url)
        } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          continuation.resume(throwing: GoogleError.cancelled)
        } else {
          continuation.resume(throwing: error ?? GoogleError.invalidResponse)
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      authSession = session
      session.start()
    }

    guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "code" })?.value
    else { throw GoogleError.invalidResponse }

    var newTokens = try await tokenRequest([
      "code": code,
      "client_id": clientID,
      "redirect_uri": redirectURI,
      "grant_type": "authorization_code",
      "code_verifier": verifier,
    ])
    newTokens.email = try? await fetchEmail(accessToken: newTokens.accessToken)
    save(newTokens)
  }

  func signOut() {
    tokens = nil
    Keychain.delete(account: "google.tokens")
    UserDefaults.standard.removeObject(forKey: Self.calendarIDKey)
  }

  // MARK: Writing

  func upsert(_ entry: CalendarEntry, existingID: String?) async throws -> String {
    let calendarID = try await tasanCalendarID()
    var body: [String: Any] = [
      "summary": entry.title,
      "description": [entry.notes, entry.deepLink.absoluteString].compactMap { $0 }.joined(separator: "\n\n"),
      "extendedProperties": ["private": ["tasanKey": entry.key]],
      "reminders": entry.alarmOffsetMinutes.map {
        ["useDefault": false, "overrides": [["method": "popup", "minutes": $0]]] as [String: Any]
      } ?? ["useDefault": false],
    ]
    if let location = entry.location { body["location"] = location }
    if entry.isAllDay {
      body["start"] = ["date": Self.dateOnly(entry.start)]
      // Google's all-day end date is exclusive.
      let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: entry.start) ?? entry.end
      body["end"] = ["date": Self.dateOnly(nextDay)]
    } else {
      body["start"] = ["dateTime": ISO8601DateFormatter().string(from: entry.start)]
      body["end"] = ["dateTime": ISO8601DateFormatter().string(from: entry.end)]
    }

    let path = "calendars/\(calendarID.urlPathEscaped)/events"
    if let existingID {
      do {
        let json = try await request("PUT", "\(path)/\(existingID.urlPathEscaped)", body: body)
        return json["id"] as? String ?? existingID
      } catch GoogleError.http(404, _) {
        // Deleted in Google Calendar: create it again below.
      } catch GoogleError.http(410, _) {}
    }
    let json = try await request("POST", path, body: body)
    guard let id = json["id"] as? String else { throw GoogleError.invalidResponse }
    return id
  }

  func delete(eventID: String) async {
    guard let calendarID = UserDefaults.standard.string(forKey: Self.calendarIDKey) else { return }
    _ = try? await request("DELETE", "calendars/\(calendarID.urlPathEscaped)/events/\(eventID.urlPathEscaped)")
  }

  // MARK: Reading

  /// Events from the user's selected Google calendars (not Tasan's own).
  func events(from start: Date, to end: Date) async throws -> [ExternalEvent] {
    let list = try await request("GET", "users/me/calendarList?minAccessRole=reader")
    let ownID = UserDefaults.standard.string(forKey: Self.calendarIDKey)
    let calendars = (list["items"] as? [[String: Any]] ?? []).filter {
      ($0["selected"] as? Bool ?? false) && ($0["id"] as? String) != ownID
    }
    let formatter = ISO8601DateFormatter()
    var result: [ExternalEvent] = []
    for calendar in calendars {
      guard let id = calendar["id"] as? String else { continue }
      let query = "timeMin=\(formatter.string(from: start).urlQueryEscaped)&timeMax=\(formatter.string(from: end).urlQueryEscaped)&singleEvents=true&orderBy=startTime&maxResults=250"
      let json = try await request("GET", "calendars/\(id.urlPathEscaped)/events?\(query)")
      for item in json["items"] as? [[String: Any]] ?? [] {
        guard item["status"] as? String != "cancelled",
          let startInfo = item["start"] as? [String: String],
          let endInfo = item["end"] as? [String: String],
          let eventStart = Self.parse(startInfo),
          let eventEnd = Self.parse(endInfo)
        else { continue }
        result.append(
          ExternalEvent(
            id: "google:\(item["id"] as? String ?? UUID().uuidString)",
            title: item["summary"] as? String ?? "",
            start: eventStart,
            end: eventEnd,
            isAllDay: startInfo["date"] != nil,
            isBusy: (item["transparency"] as? String) != "transparent",
            source: .google
          )
        )
      }
    }
    return result
  }

  // MARK: Private

  private func tasanCalendarID() async throws -> String {
    if let id = UserDefaults.standard.string(forKey: Self.calendarIDKey) { return id }
    let json = try await request("POST", "calendars", body: ["summary": AppleCalendarService.calendarTitle, "timeZone": "Europe/Helsinki"])
    guard let id = json["id"] as? String else { throw GoogleError.invalidResponse }
    UserDefaults.standard.set(id, forKey: Self.calendarIDKey)
    return id
  }

  @discardableResult
  private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
    let token = try await validAccessToken()
    var request = URLRequest(url: URL(string: "\(Self.api.absoluteString)/\(path)")!)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401 {
      // Token revoked or expired early: force a refresh next time.
      tokens?.expiresAt = .distantPast
    }
    guard (200...299).contains(status) else {
      throw GoogleError.http(status, String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
    }
    if data.isEmpty { return [:] }
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  private func validAccessToken() async throws -> String {
    guard var current = tokens else { throw GoogleError.notSignedIn }
    if current.expiresAt > Date().addingTimeInterval(60) { return current.accessToken }
    guard let clientID, let refreshToken = current.refreshToken else { throw GoogleError.notSignedIn }
    let refreshed = try await tokenRequest([
      "client_id": clientID,
      "refresh_token": refreshToken,
      "grant_type": "refresh_token",
    ])
    current.accessToken = refreshed.accessToken
    current.expiresAt = refreshed.expiresAt
    save(current)
    return current.accessToken
  }

  private func tokenRequest(_ parameters: [String: String]) async throws -> Tokens {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = parameters.map { "\($0.key)=\($0.value.urlQueryEscaped)" }.joined(separator: "&").data(using: .utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status),
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let accessToken = json["access_token"] as? String
    else {
      if status == 400 || status == 401 { signOut() }
      throw GoogleError.http(status, String(data: data, encoding: .utf8) ?? "")
    }
    return Tokens(
      accessToken: accessToken,
      refreshToken: json["refresh_token"] as? String ?? tokens?.refreshToken,
      expiresAt: Date().addingTimeInterval(json["expires_in"] as? Double ?? 3600),
      email: tokens?.email
    )
  }

  private func fetchEmail(accessToken: String) async throws -> String? {
    var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["email"] as? String
  }

  private func save(_ tokens: Tokens) {
    self.tokens = tokens
    Keychain.write(tokens, account: "google.tokens")
  }

  private static func dateOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "Europe/Helsinki")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func parse(_ info: [String: String]) -> Date? {
    if let dateTime = info["dateTime"] {
      return ISO8601DateFormatter().date(from: dateTime)
    }
    if let date = info["date"] {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = TimeZone(identifier: "Europe/Helsinki")
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter.date(from: date)
    }
    return nil
  }

  private static func randomURLSafeString(length: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    return Data(bytes).base64URLEncoded
  }

  struct Tokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var email: String?
  }
}

extension GoogleCalendarService: ASWebAuthenticationPresentationContextProviding {
  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first ?? ASPresentationAnchor()
    }
  }
}

extension Data {
  var base64URLEncoded: String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

extension String {
  var urlQueryEscaped: String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+:/?#")
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }

  var urlPathEscaped: String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/@#?")
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }
}

/// Minimal Keychain storage for OAuth tokens.
enum Keychain {
  static func write<T: Encodable>(_ value: T, account: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    delete(account: account)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "fi.tasan.app",
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: data,
    ]
    SecItemAdd(query as CFDictionary, nil)
  }

  static func read<T: Decodable>(_ type: T.Type, account: String) -> T? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "fi.tasan.app",
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  static func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "fi.tasan.app",
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
