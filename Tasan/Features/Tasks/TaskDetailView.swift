import SwiftUI
import TasanCore

struct TaskDetailView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let taskID: UUID

  @State private var isEditing = false
  @State private var isTransferring = false
  @State private var isAskingHelp = false
  @State private var isConfirmingDelete = false

  var body: some View {
    if let task = model.state.task(taskID) {
      content(task)
    } else {
      EmptyState(systemImage: "questionmark", title: String(localized: "Tehtävää ei löydy"), message: String(localized: "Se on ehkä poistettu toisella puhelimella."))
    }
  }

  private func content(_ task: FamilyTask) -> some View {
    let state = model.state
    let area = state.area(task.areaID)
    let responsible = state.member(task.responsibleID)
    let pending = state.pendingTransfer(for: .task(task.id))
    let canManage = model.meID.map { state.canTransfer(.task(task.id), actorID: $0) } ?? false

    return Screen {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        // What and when
        Card {
          if let area {
            Pill(text: area.displayName, systemImage: area.kind.symbolName, color: area.kind.color)
          }
          Text(state.displayTitle(of: task))
            .font(AppTypography.title)
            .foregroundColor(AppColor.textPrimary)
          if let subject = state.member(task.subjectMemberID) {
            Label("Koskee: \(subject.name)", systemImage: "person.crop.circle")
              .font(AppTypography.body)
              .foregroundColor(AppColor.textSecondary)
          }
          if let event = task.eventDay {
            detailRow("calendar", "Tapahtuma", eventText(task, event))
          }
          if let prep = task.prepDay, prep != task.eventDay {
            detailRow("hammer", "Valmistelu", prep.relativeText())
          }
          if let reminder = task.reminderDate() {
            detailRow("bell", "Muistutus", reminder.formatted(.dateTime.day().month().hour().minute()))
          }
          if let location = task.location {
            detailRow("mappin.and.ellipse", "Paikka", location)
          }
          if let notes = state.displayNotes(of: task) {
            Text(notes)
              .font(AppTypography.body)
              .foregroundColor(AppColor.textPrimary)
              .padding(.top, AppSpacing.xs)
          }
          if let parent = state.task(task.parentTaskID) {
            NavigationLink(value: parent.id) {
              Label("Osa tehtävää: \(state.displayTitle(of: parent))", systemImage: "arrow.turn.left.up")
                .font(AppTypography.caption.weight(.semibold))
            }
          }
        }

        // Who
        Card {
          Text("Vastuuhenkilö")
            .font(AppTypography.caption)
            .foregroundColor(AppColor.textSecondary)
          HStack(spacing: AppSpacing.sm) {
            MemberAvatar(member: responsible, size: 44)
            VStack(alignment: .leading, spacing: 2) {
              Text(responsible?.name ?? String(localized: "Avoin, kuka tahansa voi ottaa"))
                .font(AppTypography.headline)
              if let back = task.temporaryReturn {
                Text("Väliaikaisesti, palaa \(state.member(back.memberID)?.name ?? "") \(back.day.relativeText())")
                  .font(AppTypography.caption)
                  .foregroundColor(AppColor.detail)
              }
            }
          }

          if let pending {
            HStack {
              Label("Odottaa: \(state.member(pending.toID)?.name ?? "") vastaa siirtoon", systemImage: "hourglass")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundColor(AppColor.detail)
              Spacer()
              if pending.requestedByID == model.meID {
                Button("Peru") { model.cancelTransfer(pending.id) }.font(AppTypography.caption.weight(.semibold))
              } else if pending.toID == model.meID {
                Button("Hyväksy") { model.acceptTransfer(pending.id) }.font(AppTypography.caption.weight(.semibold))
              }
            }
          }

          if task.status == .open {
            if task.responsibleID == nil {
              PrimaryButton(title: String(localized: "Ota itselle"), systemImage: "hand.raised.fill") { model.take(task.id) }
            } else if canManage && pending == nil {
              SecondaryButton(title: String(localized: "Siirrä vastuu"), systemImage: "arrow.left.arrow.right") { isTransferring = true }
            }
            if task.responsibleID != nil && canManage {
              HStack(spacing: AppSpacing.md) {
                Button("Pyydä apua") { isAskingHelp = true }
                Spacer()
                Button("Tee avoimeksi") { model.release(task.id) }
              }
              .font(AppTypography.bodyMedium)
              .foregroundColor(AppColor.primaryForeground)
              .padding(.top, AppSpacing.xxs)
            }
          }
        }

        // Help sub-tasks
        let subtasks = state.subtasks(of: task.id)
        if !subtasks.isEmpty {
          SectionHeader(title: String(localized: "Osatehtävät"))
          Card {
            ForEach(subtasks) { sub in
              NavigationLink(value: sub.id) { TaskRow(task: sub) }.buttonStyle(.plain)
            }
          }
        }

        if task.status == .open {
          PrimaryButton(title: String(localized: "Merkitse hoidetuksi"), systemImage: "checkmark.circle.fill") {
            model.complete(task.id)
            dismiss()
          }
        } else {
          SecondaryButton(title: task.status == .done ? String(localized: "Hoidettu. Avaa uudelleen") : String(localized: "Ohitettu. Palauta"), systemImage: "arrow.uturn.backward") {
            model.reopen(task.id)
          }
        }

        // History
        SectionHeader(title: String(localized: "Historia"))
        Card {
          ForEach(state.history(for: .task(task.id))) { entry in
            HistoryRow(entry: entry)
          }
        }

        Button(task.occurrenceKey != nil ? String(localized: "Ohita tänä vuonna") : String(localized: "Poista tehtävä"), role: .destructive) {
          isConfirmingDelete = true
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
      }
    }
    .navigationTitle(Text(verbatim: ""))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button("Muokkaa") { isEditing = true }
    }
    .sheet(isPresented: $isEditing) {
      TaskEditorView(task: task, displayTitle: state.displayTitle(of: task), displayNotes: state.displayNotes(of: task))
    }
    .sheet(isPresented: $isTransferring) { TransferSheet(subject: .task(task.id)) }
    .sheet(isPresented: $isAskingHelp) { HelpSheet(parent: task) }
    .confirmationDialog("Haluatko varmasti?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
      Button(task.occurrenceKey != nil ? String(localized: "Ohita") : String(localized: "Poista"), role: .destructive) {
        model.delete(task)
        dismiss()
      }
    } message: {
      Text(task.occurrenceKey != nil ? String(localized: "Vuosikello ei luo tätä uudelleen tänä vuonna.") : String(localized: "Tehtävä poistuu molemmilta."))
    }
  }

  private func eventText(_ task: FamilyTask, _ day: Day) -> String {
    guard let minutes = task.eventMinutes else { return day.relativeText() }
    return day.relativeText() + " " + String(localized: "klo \(DateText.time(minutes: minutes))")
  }

  private func detailRow(_ icon: String, _ label: LocalizedStringKey, _ value: String) -> some View {
    HStack(spacing: AppSpacing.sm) {
      Image(systemName: icon)
        .frame(width: 22)
        .foregroundColor(AppColor.primaryForeground)
      Text(label)
        .foregroundColor(AppColor.textSecondary)
      Spacer()
      Text(value)
        .foregroundColor(AppColor.textPrimary)
        .multilineTextAlignment(.trailing)
    }
    .font(AppTypography.body)
  }
}

struct HistoryRow: View {
  @Environment(AppModel.self) private var model
  let entry: HistoryEntry

  var body: some View {
    let state = model.state
    HStack(alignment: .top, spacing: AppSpacing.sm) {
      Image(systemName: icon)
        .foregroundColor(AppColor.textSecondary)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(text(state))
          .font(AppTypography.body)
          .foregroundColor(AppColor.textPrimary)
        if let note = entry.note, entry.kind != .created {
          Text(noteText(note)).font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
        }
        Text(entry.date.formatted(.dateTime.day().month().hour().minute()))
          .font(AppTypography.caption)
          .foregroundColor(AppColor.textSecondary)
      }
    }
  }

  private var icon: String {
    switch entry.kind {
    case .created: return "plus.circle"
    case .transferRequested: return "paperplane"
    case .transferred: return "arrow.left.arrow.right"
    case .transferDeclined: return "xmark.circle"
    case .transferCancelled: return "minus.circle"
    case .returned: return "arrow.uturn.backward"
    case .taken: return "hand.raised"
    case .released: return "hand.raised.slash"
    case .helpRequested: return "person.2"
    case .completed: return "checkmark.circle"
    case .reopened: return "arrow.counterclockwise"
    }
  }

  /// Marker notes are translated; anything a person wrote is quoted as written.
  private func noteText(_ note: String) -> String {
    switch note {
    case HistoryEntry.skippedNote: return String(localized: "Ohitettu")
    case HistoryEntry.yearClockNote: return String(localized: "Vuosikello")
    default: return String(localized: "”\(note)”", comment: "A quoted message")
    }
  }

  private func text(_ state: FamilyState) -> String {
    let actor = state.member(entry.actorID)?.name
    let from = state.member(entry.fromID)?.name ?? String(localized: "avoin")
    let to = state.member(entry.toID)?.name ?? String(localized: "avoin")
    switch entry.kind {
    case .created:
      return entry.note == HistoryEntry.yearClockNote
        ? String(localized: "Vuosikello loi, vastuu: \(to)")
        : String(localized: "\(actor ?? String(localized: "Joku")) loi, vastuu: \(to)")
    case .transferRequested: return String(localized: "\(actor ?? "") pyysi: \(from) → \(to)")
    case .transferred: return String(localized: "Vastuu siirtyi: \(from) → \(to)")
    case .transferDeclined: return String(localized: "\(to) kieltäytyi siirrosta")
    case .transferCancelled: return String(localized: "Siirtopyyntö peruttiin")
    case .returned: return String(localized: "Väliaikainen siirto päättyi, vastuu palasi: \(to)")
    case .taken: return String(localized: "\(to) otti hoitaakseen")
    case .released: return String(localized: "\(from) avasi tehtävän kaikille")
    case .helpRequested: return String(localized: "\(actor ?? "") pyysi apua: \(entry.note ?? "")")
    case .completed:
      return entry.note == HistoryEntry.skippedNote
        ? String(localized: "Ohitettu tänä vuonna")
        : String(localized: "\(actor ?? "") kuittasi hoidetuksi")
    case .reopened: return String(localized: "\(actor ?? "") avasi uudelleen")
    }
  }
}
