import Foundation

/*
 * User-facing text from the core rules. The Finnish source string
 * is the key: the app points `lookup` at its String Catalog
 * (Core.xcstrings) at launch, and tests keep the Finnish default.
 * Stored data stays Finnish so both phones of a family agree on it
 * even when they run in different languages; it is translated only
 * when shown.
 */
public enum CoreText {
  public static var lookup: (String) -> String = { $0 }

  public static func text(_ finnish: String) -> String {
    lookup(finnish)
  }

  /// Fills `%@` (or positional `%1$@`) placeholders with `arguments`, after translating the format.
  public static func format(_ finnish: String, _ arguments: String...) -> String {
    fill(lookup(finnish), arguments)
  }

  static func fill(_ format: String, _ arguments: [String]) -> String {
    var result = ""
    var next = 0
    var rest = Substring(format)
    while let percent = rest.firstIndex(of: "%") {
      result += rest[..<percent]
      let after = rest[rest.index(after: percent)...]
      if after.hasPrefix("@") {
        result += next < arguments.count ? arguments[next] : ""
        next += 1
        rest = after.dropFirst()
      } else if let dollar = after.firstIndex(of: "$"), let position = Int(after[..<dollar]),
        after[after.index(after: dollar)...].hasPrefix("@")
      {
        result += position >= 1 && position <= arguments.count ? arguments[position - 1] : ""
        rest = after[after.index(dollar, offsetBy: 2)...]
      } else if after.hasPrefix("%") {
        result += "%"
        rest = after.dropFirst()
      } else {
        result += "%"
        rest = after
      }
    }
    return result + rest
  }
}

// MARK: - Display text for stored data

public extension AreaKind {
  /// The area's name in the current language.
  var title: String { CoreText.text(finnishTitle) }
}

public extension Area {
  /// A default name is shown in the current language; a name the family wrote is shown as written.
  var displayName: String {
    name == kind.finnishTitle ? kind.title : name
  }
}

public extension YearTemplate {
  /// The built-in template this one was copied from, while its text is unedited.
  private var builtIn: YearTemplate? {
    builtInKey.flatMap { BuiltInTemplates.byKey[$0] }
  }

  var displayTitle: String {
    guard let builtIn, builtIn.title == title else { return title }
    return CoreText.text(title)
  }

  var displayNotes: String? {
    guard let notes, let builtIn, builtIn.notes == notes else { return notes }
    return CoreText.text(notes)
  }
}

public extension YearClock.Occurrence {
  func displayTitle(in state: FamilyState) -> String {
    YearClock.taskTitle(template.displayTitle, subject: state.member(memberID)?.name)
  }
}

public extension FamilyState {
  func template(_ id: UUID?) -> YearTemplate? {
    guard let id else { return nil }
    return templates.first { $0.id == id }
  }

  /// A year clock task keeps the stored Finnish title in data and shows it translated until someone edits it.
  func displayTitle(of task: FamilyTask) -> String {
    guard task.source == .yearClock, let template = template(task.templateID) else { return task.title }
    let subject = member(task.subjectMemberID)?.name
    guard task.title == YearClock.taskTitle(template.title, subject: subject) else { return task.title }
    return YearClock.taskTitle(template.displayTitle, subject: subject)
  }

  func displayNotes(of task: FamilyTask) -> String? {
    guard task.source == .yearClock, let template = template(task.templateID), task.notes == template.notes else {
      return task.notes
    }
    return template.displayNotes
  }
}
