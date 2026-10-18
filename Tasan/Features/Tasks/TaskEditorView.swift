import SwiftUI
import TasanCore

/// Create or edit a task: title, area, responsible, event day, preparation day, reminder.
struct TaskEditorView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private let original: FamilyTask?
  private var source: TaskSource

  @State private var title: String
  @State private var areaID: UUID?
  @State private var responsibleID: UUID?
  @State private var subjectID: UUID?
  @State private var hasEvent: Bool
  @State private var eventDate: Date
  @State private var hasTime: Bool
  @State private var durationMinutes: Int
  @State private var hasPrep: Bool
  @State private var prepDate: Date
  @State private var hasCustomReminder: Bool
  @State private var reminder: Date
  @State private var location: String
  @State private var notes: String
  @State private var didSetResponsible = false

  init(task: FamilyTask?) {
    original = task
    source = task?.source ?? .manual
    let calendar = Calendar.finnish
    let event = task?.eventDay.map { day in task?.eventMinutes.map { day.date(minutes: $0) } ?? day.date(minutes: 12 * 60) }
      ?? calendar.date(byAdding: .day, value: 7, to: Date())!
    _title = State(initialValue: task?.title ?? "")
    _areaID = State(initialValue: task?.areaID)
    _responsibleID = State(initialValue: task?.responsibleID)
    _subjectID = State(initialValue: task?.subjectMemberID)
    _hasEvent = State(initialValue: task == nil || task?.eventDay != nil)
    _eventDate = State(initialValue: event)
    _hasTime = State(initialValue: task?.eventMinutes != nil)
    _durationMinutes = State(initialValue: task?.eventDurationMinutes ?? 60)
    _hasPrep = State(initialValue: task?.prepDay != nil && task?.prepDay != task?.eventDay)
    _prepDate = State(initialValue: task?.prepDay?.date() ?? calendar.date(byAdding: .day, value: -3, to: event)!)
    _hasCustomReminder = State(initialValue: task?.reminder != nil)
    _reminder = State(initialValue: task?.reminderDate() ?? event)
    _location = State(initialValue: task?.location ?? "")
    _notes = State(initialValue: task?.notes ?? "")
    _didSetResponsible = State(initialValue: task != nil)
  }

  /// Prefilled from a photo ("Kuvasta tapahtumaksi").
  init(imported: ImportedEvent, areaID: UUID?, prepLeadDays: Int) {
    self.init(task: nil)
    source = .image
    let start = imported.start ?? Calendar.finnish.date(byAdding: .day, value: 7, to: Date())!
    _title = State(initialValue: imported.title)
    _areaID = State(initialValue: areaID)
    _eventDate = State(initialValue: start)
    _hasTime = State(initialValue: !imported.isAllDay && imported.start != nil)
    if let end = imported.end, let begin = imported.start, end > begin {
      _durationMinutes = State(initialValue: Int(end.timeIntervalSince(begin) / 60))
    }
    _hasPrep = State(initialValue: prepLeadDays > 0)
    _prepDate = State(initialValue: Calendar.finnish.date(byAdding: .day, value: -prepLeadDays, to: start)!)
    _location = State(initialValue: imported.location ?? "")
    let preparation = imported.preparation.map { "Valmistele: \($0)" }
    _notes = State(initialValue: [preparation, imported.notes].compactMap { $0 }.joined(separator: "\n"))
  }

  var body: some View {
    let state = model.state
    NavigationStack {
      Form {
        Section {
          TextField("Otsikko, esim. Osta lahja Eetun synttäreille", text: $title, axis: .vertical)
            .font(AppTypography.headline)
          Picker("Osa-alue", selection: $areaID) {
            Text("Ei osa-aluetta").tag(UUID?.none)
            ForEach(state.areas.filter(\.enabled)) { area in
              Label(area.name, systemImage: area.kind.symbolName).tag(UUID?.some(area.id))
            }
          }
          .onChange(of: areaID) { _, newArea in
            // New tasks go to the area owner unless someone was picked by hand.
            if !didSetResponsible, let owner = state.area(newArea)?.ownerID { responsibleID = owner }
          }
          Picker("Vastuuhenkilö", selection: Binding(get: { responsibleID }, set: { responsibleID = $0; didSetResponsible = true })) {
            Text("Avoin, kuka tahansa voi ottaa").tag(UUID?.none)
            ForEach(state.responsibleCandidates) { member in
              Text(member.name).tag(UUID?.some(member.id))
            }
          }
          if !state.children.isEmpty {
            Picker("Koskee", selection: $subjectID) {
              Text("Koko perhettä").tag(UUID?.none)
              ForEach(state.children) { child in
                Text(child.name).tag(UUID?.some(child.id))
              }
            }
          }
        }

        Section("Tapahtuma") {
          Toggle("Tapahtumalla on päivä", isOn: $hasEvent)
          if hasEvent {
            DatePicker("Päivä", selection: $eventDate, displayedComponents: .date)
            Toggle("Kellonaika", isOn: $hasTime)
            if hasTime {
              DatePicker("Alkaa", selection: $eventDate, displayedComponents: .hourAndMinute)
              Stepper("Kesto \(durationText)", value: $durationMinutes, in: 15...600, step: 15)
            }
            TextField("Paikka", text: $location)
          }
        }

        Section {
          Toggle("Erillinen valmistelupäivä", isOn: $hasPrep)
          if hasPrep {
            DatePicker("Valmistelu", selection: $prepDate, in: ...eventDate, displayedComponents: .date)
          }
          Toggle("Oma muistutusaika", isOn: $hasCustomReminder)
          if hasCustomReminder {
            DatePicker("Muistutus", selection: $reminder)
          }
        } header: {
          Text("Valmistelu ja muistutus")
        } footer: {
          Text("Valmistelu näkyy kalenterissa omana merkintänään. Ilman omaa aikaa muistutus tulee valmistelupäivänä klo 9.")
        }

        Section("Muistiinpanot") {
          TextField("Lisätiedot", text: $notes, axis: .vertical)
            .lineLimit(3...8)
        }
      }
      .environment(\.locale, Locale(identifier: "fi_FI"))
      .scrollContentBackground(.hidden)
      .background(AppColor.background)
      .navigationTitle(original == nil ? "Uusi tehtävä" : "Muokkaa")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Peru") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Tallenna") { save() }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .onAppear {
        if original == nil, !didSetResponsible {
          responsibleID = state.area(areaID)?.ownerID ?? model.meID
        }
      }
    }
  }

  private var durationText: String {
    durationMinutes % 60 == 0 ? "\(durationMinutes / 60) h" : "\(durationMinutes / 60) h \(durationMinutes % 60) min"
  }

  private func save() {
    let calendar = Calendar.finnish
    var task = original ?? FamilyTask(title: "", source: source)
    task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    task.areaID = areaID
    task.responsibleID = responsibleID
    task.subjectMemberID = subjectID
    if hasEvent {
      task.eventDay = Day(date: eventDate, calendar: calendar)
      let parts = calendar.dateComponents([.hour, .minute], from: eventDate)
      task.eventMinutes = hasTime ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : nil
      task.eventDurationMinutes = hasTime ? durationMinutes : nil
      task.location = location.isEmpty ? nil : location
    } else {
      task.eventDay = nil
      task.eventMinutes = nil
      task.eventDurationMinutes = nil
      task.location = nil
    }
    task.prepDay = hasPrep ? Day(date: prepDate, calendar: calendar) : nil
    task.reminder = hasCustomReminder ? reminder : nil
    task.notes = notes.isEmpty ? nil : notes

    // Changing the responsible person here is a transfer; that goes through approval.
    if let original, original.responsibleID != task.responsibleID, let receiver = task.responsibleID, receiver != model.meID {
      task.responsibleID = original.responsibleID
      model.save(task, isNew: false)
      model.requestTransfer(.task(task.id), to: receiver, message: nil, returnDay: nil, direct: model.state.mayTransferDirectly(actorID: model.meID ?? UUID()))
    } else {
      model.save(task, isNew: original == nil)
    }
    dismiss()
  }
}
