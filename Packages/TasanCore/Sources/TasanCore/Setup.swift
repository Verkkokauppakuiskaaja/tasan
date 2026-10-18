import Foundation

public extension FamilyState {
  /*
   * A new family: the creating adult is the admin, the five MVP
   * areas exist, and the built-in year clock is copied in so the
   * family can edit its own copy. Areas start owned by the admin;
   * the meeting or onboarding is where they get shared out.
   */
  static func newFamily(
    name: String,
    admin: Member,
    enabledAreas: Set<AreaKind> = Set(AreaKind.allCases),
    now: Date = Date()
  ) -> FamilyState {
    var state = FamilyState()
    var admin = admin
    admin.role = .adminAdult
    state.save(Family(name: name, createdAt: now), now: now)
    state.save(admin, now: now)
    for kind in AreaKind.allCases {
      state.save(Area(kind: kind, ownerID: admin.id, enabled: enabledAreas.contains(kind)), now: now)
    }
    for template in BuiltInTemplates.all() {
      state.save(template.withFamilyScopedID(state.family!.id), now: now)
    }
    return state
  }

  /// Adds built-in templates that a newer app version ships and the family does not have yet.
  mutating func addMissingBuiltInTemplates(now: Date = Date()) {
    let existing = Set(templates.compactMap(\.builtInKey))
    guard let familyID = family?.id else { return }
    for template in BuiltInTemplates.all() where !existing.contains(template.builtInKey ?? "") {
      save(template.withFamilyScopedID(familyID), now: YearClock.generatedStamp)
    }
  }

  /// Daily housekeeping: temporary transfers come back and the year clock fills the horizon.
  @discardableResult
  mutating func runDailyMaintenance(today: Day, actorID: UUID?, now: Date = Date()) -> (returned: [TransferSubject], created: [FamilyTask]) {
    let returned = processTemporaryReturns(today: today, now: now)
    let created = YearClock().generateTasks(in: &self, today: today, actorID: actorID, now: now)
    return (returned, created)
  }
}

public extension UUID {
  /*
   * A UUID derived from a string. Both phones run the year clock,
   * so a generated task must get the same id on both; otherwise
   * syncing would leave the family with two copies.
   */
  init(deterministic key: String) {
    func fnv1a(_ seed: UInt64) -> UInt64 {
      var hash = seed
      for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
      }
      return hash
    }
    let high = fnv1a(0xcbf29ce484222325)
    let low = fnv1a(0x84222325cbf29ce4 ^ high)
    var bytes = [UInt8](repeating: 0, count: 16)
    for i in 0..<8 {
      bytes[i] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(i)))
      bytes[8 + i] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(i)))
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style
    bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
    self.init(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}

extension YearTemplate {
  /// Built-in templates get the same id on every phone of the family.
  func withFamilyScopedID(_ familyID: UUID) -> YearTemplate {
    var copy = self
    if let key = builtInKey {
      copy.id = UUID(deterministic: "\(familyID)|template|\(key)")
    }
    return copy
  }
}
