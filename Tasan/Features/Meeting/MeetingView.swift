import SwiftUI
import TasanCore

/*
 * "Perhepalaveri": the app prepares the agenda, the adults go
 * through it together (on one phone or both) and act on the spot:
 * take open tasks, move responsibilities, mark things done. At
 * the end the app shows what was agreed and saves it.
 */
struct MeetingView: View {
  @Environment(AppModel.self) private var model
  @State private var kind: MeetingKind = .weekly
  @State private var log: MeetingChangeLog?
  @State private var summary: [String]?
  @State private var transferring: UUID?

  var body: some View {
    let state = model.state
    let agenda = MeetingAgenda.make(kind, state: state, today: .today(), busy: state.busyIntervals)

    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          TitleSection(
            title: kind == .weekly ? "Viikkopalaveri" : "Kuukausipalaveri",
            subtitle: kind == .weekly
              ? "Seuraavat 7 päivää, noin 15 minuuttia"
              : "Seuraavat 6 viikkoa ja vuosikellon tulevat asiat, noin 30 minuuttia"
          )

          Picker("Palaveri", selection: $kind) {
            Text("Viikko").tag(MeetingKind.weekly)
            Text("Kuukausi").tag(MeetingKind.monthly)
          }
          .pickerStyle(.segmented)

          if log == nil {
            PrimaryButton(title: "Aloita palaveri", systemImage: "play.fill") {
              log = MeetingChangeLog(startedAt: Date())
            }
          } else {
            Label("Palaveri käynnissä. Muutokset kirjataan yhteenvetoon.", systemImage: "record.circle")
              .font(AppTypography.caption.weight(.semibold))
              .foregroundColor(AppColor.detail)
          }

          if let previous = agenda.previous, !previous.agreedChanges.isEmpty {
            SectionHeader(title: "Viimeksi sovittiin", subtitle: previous.date.formatted(.dateTime.locale(Locale(identifier: "fi_FI")).day().month()))
            Card {
              ForEach(previous.agreedChanges, id: \.self) { Text("• \($0)").font(AppTypography.body) }
            }
          }

          // Overlaps and pending requests first: they need a decision.
          if !agenda.overlaps.isEmpty {
            SectionHeader(title: "Päällekkäisyydet", count: agenda.overlaps.count)
            ForEach(agenda.overlaps) { overlap in
              Card {
                Text(state.task(overlap.taskID)?.title ?? "").font(AppTypography.headline)
                Text("\(state.member(overlap.memberID)?.name ?? "") on silloin varattu\(overlap.conflictingTitle.map { ": \($0)" } ?? "").")
                  .font(AppTypography.body)
                  .foregroundColor(AppColor.textSecondary)
                if let suggested = state.member(overlap.suggestedMemberID) {
                  SecondaryButton(title: "Siirrä: \(suggested.name)", systemImage: "arrow.left.arrow.right") {
                    model.requestTransfer(.task(overlap.taskID), to: suggested.id, message: "Sovittu palaverissa", returnDay: nil, direct: state.mayTransferDirectly(actorID: model.meID ?? UUID()))
                  }
                }
              }
            }
          }

          if !agenda.pendingTransfers.isEmpty {
            SectionHeader(title: "Odottavat siirrot", count: agenda.pendingTransfers.count)
            Card {
              ForEach(agenda.pendingTransfers) { request in
                HStack {
                  VStack(alignment: .leading) {
                    Text(state.subjectTitle(request.subject)).font(AppTypography.bodyMedium)
                    Text("\(state.member(request.fromID)?.name ?? "avoin") → \(state.member(request.toID)?.name ?? "")")
                      .font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
                  }
                  Spacer()
                  if request.toID == model.meID {
                    Button("Hyväksy") { model.acceptTransfer(request.id) }.buttonStyle(.borderedProminent)
                  }
                }
              }
            }
          }

          SectionHeader(title: "Kenellä on mitäkin", subtitle: "\(agenda.from.finnishShortString)–\(agenda.to.finnishShortString)")
          ForEach(agenda.upcomingByResponsible(order: state.adults.map(\.id))) { group in
            let member = state.member(group.memberID)
            Card {
              HStack {
                MemberAvatar(member: member, size: 30)
                Text(member?.name ?? "Avoimet").font(AppTypography.headline)
                Spacer()
                Text("\(group.tasks.count)").font(AppTypography.headline).foregroundColor(AppColor.textSecondary)
              }
              ForEach(group.tasks) { task in
                meetingTaskRow(task)
              }
            }
          }
          if agenda.upcoming.isEmpty {
            EmptyState(systemImage: "checkmark.seal", title: "Rauhallinen jakso", message: "Ei tehtäviä tällä aikavälillä.")
          }

          if !agenda.overdue.isEmpty {
            SectionHeader(title: "Myöhässä", count: agenda.overdue.count)
            Card {
              ForEach(agenda.overdue) { meetingTaskRow($0) }
            }
          }

          if !agenda.birthdays.isEmpty {
            SectionHeader(title: "Synttärit")
            Card {
              ForEach(agenda.birthdays) { item in
                Label("\(state.member(item.memberID)?.name ?? "") \(item.day.relativeText())", systemImage: "gift.fill")
                  .font(AppTypography.body)
              }
            }
          }

          if kind == .monthly && !agenda.comingFromYearClock.isEmpty {
            SectionHeader(title: "Vuosikellosta tulossa", subtitle: "Luodaan automaattisesti ajoissa")
            Card {
              ForEach(agenda.comingFromYearClock, id: \.key) { occurrence in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.template.title + (state.member(occurrence.memberID).map { ": \($0.name)" } ?? ""))
                      .font(AppTypography.bodyMedium)
                    Text("\(occurrence.eventDay.relativeText()) · valmistelu \(occurrence.prepDay.relativeText())")
                      .font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
                  }
                  Spacer()
                  Button("Luo nyt") { model.createNow(occurrence) }
                    .font(AppTypography.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
              }
            }
          }

          SectionHeader(title: kind == .weekly ? "Kuorma tällä viikolla" : "Miten jako on mennyt")
          Card {
            ForEach(agenda.load.rows) { row in
              HStack {
                MemberAvatar(member: state.member(row.memberID), size: 26)
                Text(state.member(row.memberID)?.name ?? "")
                Spacer()
                Text("\(row.openTasks) avointa · \(row.completedInPeriod) hoidettu")
                  .font(AppTypography.caption)
                  .foregroundColor(AppColor.textSecondary)
              }
            }
            if kind == .monthly {
              Text("Vaihtakaa tarvittaessa osa-aluevastuita Jako-näkymässä tai muokatkaa vuosikellon malleja.")
                .font(AppTypography.caption)
                .foregroundColor(AppColor.textSecondary)
            }
          }

          if log != nil {
            PrimaryButton(title: "Lopeta ja näytä yhteenveto", systemImage: "checkmark") {
              summary = log?.changes(in: model.state) ?? []
            }
          }
        }
      }
      .navigationDestination(for: UUID.self) { TaskDetailView(taskID: $0) }
      .sheet(item: Binding(get: { transferring.map(IdentifiedID.init) }, set: { transferring = $0?.id })) { item in
        TransferSheet(subject: .task(item.id))
      }
      .sheet(isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
        MeetingSummaryView(kind: kind, changes: summary ?? []) {
          model.saveMeeting(kind: kind, changes: summary ?? [])
          summary = nil
          log = nil
        }
      }
    }
  }

  private func meetingTaskRow(_ task: FamilyTask) -> some View {
    HStack(spacing: AppSpacing.xs) {
      NavigationLink(value: task.id) { TaskRow(task: task, showsResponsible: false) }
        .buttonStyle(.plain)
      Menu {
        if task.responsibleID == nil {
          Button("Ota itselle", systemImage: "hand.raised") { model.take(task.id) }
        } else {
          Button("Siirrä vastuu", systemImage: "arrow.left.arrow.right") { transferring = task.id }
        }
        Button("Kuittaa hoidetuksi", systemImage: "checkmark.circle") { model.complete(task.id) }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.title3)
          .foregroundColor(AppColor.primaryForeground)
      }
    }
  }
}

struct MeetingSummaryView: View {
  let kind: MeetingKind
  let changes: [String]
  let onSave: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          TitleSection(title: "Sovitut muutokset", subtitle: kind == .weekly ? "Viikkopalaveri" : "Kuukausipalaveri")
          Card {
            if changes.isEmpty {
              Text("Ei muutoksia. Kaikki pysyy ennallaan.").foregroundColor(AppColor.textSecondary)
            }
            ForEach(changes, id: \.self) { change in
              Label(change, systemImage: "checkmark.circle.fill")
                .font(AppTypography.body)
            }
          }
          PrimaryButton(title: "Tallenna ja lopeta", systemImage: "checkmark") {
            onSave()
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
