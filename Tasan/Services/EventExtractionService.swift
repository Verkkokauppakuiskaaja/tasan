import Foundation
import TasanCore
import UIKit

/*
 * "Kuvasta tapahtumaksi": Apple Vision reads the text on the phone,
 * and only that text goes to Tasan!'s own Cloudflare Worker
 * (Worker/), which asks Claude for the events in it, the family
 * area and what to prepare. The photo itself never leaves the phone.
 */
struct ImportedEvent: Identifiable, Equatable {
  let id = UUID()
  var title: String
  var start: Date?
  var end: Date?
  var isAllDay: Bool
  var location: String?
  var notes: String?
  /// Claude's guess of the family area; nil when it fits none.
  var areaKind: AreaKind?
  /// What to do or bring beforehand, when the source says so.
  var preparation: String?
  var isComplete: Bool
}

final class EventExtractionService {
  /*
   * Host and key come from Config/Tasan.xcconfig through Info.plist.
   * The key ships inside the app, so it is a speed bump against
   * bots, not a secret.
   */
  private static let endpoint: URL? = {
    guard let host = infoValue("TASAN_AI_HOST") else { return nil }
    return URL(string: "https://\(host)/extract-event")
  }()

  private static let appKey = infoValue("TASAN_AI_KEY")

  private static func infoValue(_ key: String) -> String? {
    let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty || value.hasPrefix("$(") ? nil : value
  }

  private let ocr = OCRService()
  private let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 75
    configuration.waitsForConnectivity = true
    return URLSession(configuration: configuration)
  }()

  func events(in image: UIImage) async throws -> [ImportedEvent] {
    let context = DeviceContext.current
    let text = try await ocr.extractText(from: image, preferredLanguages: context.preferredOCRLanguages)
    return try await events(inText: text, context: context)
  }

  func events(inText text: String, context: DeviceContext = .current) async throws -> [ImportedEvent] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ExtractionError.noText }
    guard trimmed.count <= 10_000 else { throw ExtractionError.tooLong }

    guard let endpoint = Self.endpoint, let appKey = Self.appKey else { throw ExtractionError.notConfigured }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(appKey, forHTTPHeaderField: "X-Tasan-Key")
    request.httpBody = try JSONEncoder().encode(Request(ocrText: trimmed, deviceContext: context))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.code == .timedOut {
      throw ExtractionError.timedOut
    } catch is URLError {
      throw ExtractionError.network
    }

    guard let http = response as? HTTPURLResponse else { throw ExtractionError.invalidResponse }
    switch http.statusCode {
    case 200...299: break
    case 429: throw ExtractionError.busy
    case 413: throw ExtractionError.tooLong
    default: throw ExtractionError.serviceUnavailable
    }

    let decoded = try JSONDecoder().decode(Response.self, from: data)
    let events = decoded.events ?? decoded.event.map { [$0] } ?? []
    guard !events.isEmpty else { throw ExtractionError.noEvents }

    return events.map { event in
      let start = Self.parse(event.startDate)
      let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return ImportedEvent(
        title: title,
        start: start,
        end: Self.parse(event.endDate),
        isAllDay: event.isAllDay ?? false,
        location: event.location,
        notes: event.notes,
        areaKind: event.areaKind.flatMap(AreaKind.init(rawValue:)),
        preparation: event.preparation,
        isComplete: event.status == "ready" && start != nil && !title.isEmpty
      )
    }
  }

  private static func parse(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private struct Request: Encodable {
    let ocrText: String
    let deviceContext: DeviceContext
  }

  private struct Response: Decodable {
    let ok: Bool?
    let event: Event?
    let events: [Event]?
  }

  private struct Event: Decodable {
    let status: String?
    let title: String?
    let startDate: String?
    let endDate: String?
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let areaKind: String?
    let preparation: String?
  }
}

enum ExtractionError: LocalizedError {
  case noText
  case tooLong
  case noEvents
  case network
  case timedOut
  case busy
  case serviceUnavailable
  case invalidResponse
  case notConfigured

  var errorDescription: String? {
    switch self {
    case .noText: return "Kuvasta ei löytynyt luettavaa tekstiä."
    case .tooLong: return "Kuvassa on liikaa tekstiä. Rajaa kuva tapahtuman kohtaan."
    case .noEvents: return "Kuvasta ei löytynyt tapahtumaa. Voit lisätä sen käsin."
    case .network: return "Palveluun ei saatu yhteyttä. Tarkista verkkoyhteys."
    case .timedOut: return "Lukeminen kesti liian kauan. Yritä uudelleen."
    case .busy: return "Palvelu on ruuhkainen. Odota hetki ja yritä uudelleen."
    case .serviceUnavailable: return "Palvelu ei ole juuri nyt käytettävissä."
    case .invalidResponse: return "Palvelu palautti odottamattoman vastauksen."
    case .notConfigured: return "Kuvasta tapahtumaksi -palvelua ei ole määritetty tähän versioon (TASAN_AI_HOST puuttuu)."
    }
  }
}
