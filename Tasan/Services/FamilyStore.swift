import Foundation
import TasanCore

/*
 * Local storage: the whole family state as one JSON file in
 * Application Support. A family has at most a few thousand small
 * records, so writing the file on each change is cheap, and the
 * same Codable values go to CloudKit as record payloads.
 */
struct FamilyStore {
  private let url: URL

  init(fileName: String = "family.json") {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    url = directory.appendingPathComponent(fileName)
  }

  func load() -> FamilyState {
    guard let data = try? Data(contentsOf: url) else { return FamilyState() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return (try? decoder.decode(FamilyState.self, from: data)) ?? FamilyState()
  }

  func save(_ state: FamilyState) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    guard let data = try? encoder.encode(state) else { return }
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  func reset() {
    try? FileManager.default.removeItem(at: url)
  }
}

/// Small per-device settings that never sync.
enum DeviceSettings {
  private static let defaults = UserDefaults.standard

  /// Which family member uses this phone.
  static var currentMemberID: UUID? {
    get { defaults.string(forKey: "tasan.currentMemberID").flatMap(UUID.init(uuidString:)) }
    set { defaults.set(newValue?.uuidString, forKey: "tasan.currentMemberID") }
  }

  static var shareBusyTitles: Bool {
    get { defaults.object(forKey: "tasan.shareBusyTitles") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "tasan.shareBusyTitles") }
  }

  static var aiConsentAccepted: Bool {
    get { defaults.bool(forKey: "tasan.aiConsentAccepted") }
    set { defaults.set(newValue, forKey: "tasan.aiConsentAccepted") }
  }

  static var lastMaintenanceDay: String? {
    get { defaults.string(forKey: "tasan.lastMaintenanceDay") }
    set { defaults.set(newValue, forKey: "tasan.lastMaintenanceDay") }
  }

  /// Transfer request ids already announced with a notification on this phone.
  static var notifiedTransferIDs: Set<String> {
    get { Set(defaults.stringArray(forKey: "tasan.notifiedTransfers") ?? []) }
    set { defaults.set(Array(newValue.suffix(500)), forKey: "tasan.notifiedTransfers") }
  }
}
