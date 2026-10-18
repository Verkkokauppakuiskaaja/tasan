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
      EmptyState(systemImage: "questionmark", title: "Tehtävää ei löydy", message: "Se on ehkä poistettu toisella puhelimella.")
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
            Pill(text: area.name, systemImage: area.kind.symbolName, color: area.kind.color)
          }
          Text(task.title)
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
            detailRow("bell", "Muistutus", reminder.formatted(.dateTime.locale(Locale(identifier: "fi_FI")).day().month().hour().minute()))
          }
          if let location = task.location {
            detailRow("mappin.and.ellipse", "Paikka", location)
          }
          if let notes = task.notes {
            Text(notes)
              .font(AppTypography.body)
              .foregroundColor(AppColor.textPrimary)
              .padding(.top, AppSpacing.xs)
          }
          if let parent = state.task(task.parentTaskID) {
            NavigationLink(value: parent.id) {
              Label("Osa tehtävää: \(parent.title)", systemImage: "arrow.turn.left.up")
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
              Text(responsible?.name ?? "Avoin, kuka tahansa voi ottaa")
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
              PrimaryButton(title: "Ota itselle", systemImage: "hand.raised.fill") { model.take(task.id) }
            } else if canManage && pending == nil {
              SecondaryButton(title: "Siirrä vastuu", systemImage: "arrow.left.arrow.right") { isTransferring = true }
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
          SectionHeader(title: "Osatehtävät")
          Card {
            ForEach(subtasks) { sub in
              NavigationLink(value: sub.id) { TaskRow(task: sub) }.buttonStyle(.plain)
            }
          }
        }

        if task.status == .open {
          PrimaryButton(title: "Merkitse hoidetuksi", systemImage: "checkmark.circle.fill") {
            model.complete(task.id)
            dismiss()
          }
        } else {
          SecondaryButton(title: task.status == .done ? "Hoidettu. Avaa uudelleen" : "Ohitettu. Palauta", systemImage: "arrow.uturn.backward") {
            model.reopen(task.id)
          }
        }

        // History
        SectionHeader(title: "Historia")
        Card {
          ForEach(state.history(for: .task(task.id))) { entry in
            HistoryRow(entry: entry)
          }
        }

        Button(task.occurrenceKey != nil ? "Ohita tänä vuonna" : "Poista tehtävä", role: .destructive) {
          isConfirmingDelete = true
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
      }
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button("Muokkaa") { isEditing = true }
    }
    .sheet(isPresented: $isEditing) { TaskEditorView(task: task) }
    .sheet(isPresented: $isTransferring) { TransferSheet(subject: .task(task.id)) }
    .sheet(isPresented: $isAskingHelp) { HelpSheet(parent: task) }
    .confirmationDialog("Haluatko varmasti?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
      Button(task.occurrenceKey != nil ? "Ohita" : "Poista", role: .destructive) {
        model.delete(task)
        dismiss()
      }
    } message: {
      Text(task.occurrenceKey != nil ? "Vuosikello ei luo tätä uudelleen tänä vuonna." : "Tehtävä poistuu molemmilta.")
    }
  }

  private func eventText(_ task: FamilyTask, _ day: Day) -> String {
    guard let minutes = task.eventMinutes else { return day.relativeText() }
    return day.relativeText() + String(format: " klo %d.%02d", minutes / 60, minutes % 60)
  }

  private func detailRow(_ icon: String, _ label: String, _ value: String) -> some View {
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
          Text("”\(note)”").font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
        }
        Text(entry.date.formatted(.dateTime.locale(Locale(identifier: "fi_FI")).day().month().hour().minute()))
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

  private func text(_ state: FamilyState) -> String {
    let actor = state.member(entry.actorID)?.name
    let from = state.member(entry.fromID)?.name ?? "avoin"
    let to = state.member(entry.toID)?.name ?? "avoin"
    switch entry.kind {
    case .created: return entry.note == "Vuosikello" ? "Vuosikello loi, vastuu: \(to)" : "\(actor ?? "Joku") loi, vastuu: \(to)"
    case .transferRequested: return "\(actor ?? "") pyysi: \(from) → \(to)"
    case .transferred: return "Vastuu siirtyi: \(from) → \(to)"
    case .transferDeclined: return "\(to) kieltäytyi siirrosta"
    case .transferCancelled: return "Siirtopyyntö peruttiin"
    case .returned: return "Väliaikainen siirto päättyi, vastuu palasi: \(to)"
    case .taken: return "\(to) otti hoitaakseen"
    case .released: return "\(from) avasi tehtävän kaikille"
    case .helpRequested: return "\(actor ?? "") pyysi apua: \(entry.note ?? "")"
    case .completed: return entry.note == "Ohitettu" ? "Ohitettu tänä vuonna" : "\(actor ?? "") kuittasi hoidetuksi"
    case .reopened: return "\(actor ?? "") avasi uudelleen"
    }
  }
}
