import SwiftUI
import TasanCore

/*
 * "Siirrä vastuu": pick the receiver, add a message, optionally
 * make it temporary. The receiver approves, unless the family lets
 * admins move responsibilities directly and the admin chooses so.
 */
struct TransferSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let subject: TransferSubject

  @State private var receiverID: UUID?
  @State private var message = ""
  @State private var isTemporary = false
  @State private var returnDate = Calendar.finnish.date(byAdding: .day, value: 7, to: Date())!
  @State private var direct = false

  private let suggestions = ["Mulla työmatka, voitko ottaa?", "Mulla on silloin muuta, ehditkö sinä?", "Vaihdetaanko tämä?"]

  var body: some View {
    let state = model.state
    let current = state.currentResponsible(of: subject)
    let candidates = state.responsibleCandidates.filter { $0.id != current }
    let mayDirect = model.meID.map { state.mayTransferDirectly(actorID: $0) } ?? false

    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          TitleSection(title: "Siirrä vastuu", subtitle: state.subjectTitle(subject))

          SectionHeader(title: "Kenelle")
          ForEach(candidates) { member in
            Button {
              receiverID = member.id
            } label: {
              HStack(spacing: AppSpacing.md) {
                MemberAvatar(member: member, size: 40)
                VStack(alignment: .leading) {
                  Text(member.name).font(AppTypography.headline).foregroundColor(AppColor.textPrimary)
                  Text(loadText(member.id, state)).font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: receiverID == member.id ? "checkmark.circle.fill" : "circle")
                  .font(.title2)
                  .foregroundColor(receiverID == member.id ? AppColor.primary : AppColor.textSecondary)
              }
              .padding(AppSpacing.md)
              .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous).fill(AppColor.card))
            }
            .buttonStyle(.plain)
          }
          if candidates.isEmpty {
            Text("Perheessä ei ole vielä toista aikuista. Kutsu hänet Tänään-näkymästä.")
              .font(AppTypography.body)
              .foregroundColor(AppColor.textSecondary)
          }

          SectionHeader(title: "Viesti")
          Card {
            LabeledField("Viesti vastaanottajalle", text: $message, prompt: "Vapaaehtoinen", axis: .vertical)
            ScrollView(.horizontal, showsIndicators: false) {
              HStack {
                ForEach(suggestions, id: \.self) { text in
                  Button(text) { message = text }
                    .font(AppTypography.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
              }
            }
          }

          Card {
            Toggle("Väliaikainen siirto", isOn: $isTemporary)
              .font(AppTypography.bodyMedium)
            if isTemporary {
              DatePicker("Palaa minulle", selection: $returnDate, in: Date()..., displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "fi_FI"))
              Text("Vastuu palaa automaattisesti valittuna päivänä, esimerkiksi loman tai työmatkan jälkeen.")
                .font(AppTypography.caption)
                .foregroundColor(AppColor.textSecondary)
            }
            if mayDirect {
              Divider()
              Toggle("Siirrä suoraan ilman hyväksyntää", isOn: $direct)
                .font(AppTypography.bodyMedium)
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        PrimaryButton(title: direct ? "Siirrä" : "Lähetä pyyntö", systemImage: "paperplane.fill") {
          guard let receiverID else { return }
          let returnDay = isTemporary ? Day(date: returnDate) : nil
          if model.requestTransfer(subject, to: receiverID, message: message, returnDay: returnDay, direct: direct) {
            dismiss()
          }
        }
        .disabled(receiverID == nil)
        .padding(AppSpacing.lg)
        .background(AppColor.background)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Peru") { dismiss() } }
      }
      .onAppear {
        if receiverID == nil, candidates.count == 1 { receiverID = candidates.first?.id }
      }
    }
    .presentationDetents([.large])
  }

  private func loadText(_ memberID: UUID, _ state: FamilyState) -> String {
    let count = state.tasks.filter { $0.status == .open && $0.responsibleID == memberID }.count
    return "\(count) avointa vastuuta"
  }
}

/// "Pyydä apua": the responsibility stays, someone else does one part.
struct HelpSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let parent: FamilyTask

  @State private var title = ""
  @State private var helperID: UUID?
  @State private var hasDay = true
  @State private var day = Date()
  @State private var message = ""

  var body: some View {
    let state = model.state
    NavigationStack {
      Form {
        Section {
          TextField("Mitä pitäisi tehdä? esim. Hae lahja postista", text: $title, axis: .vertical)
          Picker("Kuka auttaa", selection: $helperID) {
            Text("Kuka tahansa (avoin)").tag(UUID?.none)
            ForEach(state.responsibleCandidates.filter { $0.id != model.meID }) { member in
              Text(member.name).tag(UUID?.some(member.id))
            }
          }
          Toggle("Päivä", isOn: $hasDay)
          if hasDay {
            DatePicker("Milloin", selection: $day, displayedComponents: .date)
          }
          TextField("Viesti", text: $message, axis: .vertical)
        } footer: {
          Text("\(parent.title) pysyy sinun vastuullasi. Auttaja saa osatehtävän omaan listaansa ja kalenteriinsa, kun hyväksyy.")
        }
      }
      .environment(\.locale, Locale(identifier: "fi_FI"))
      .navigationTitle("Pyydä apua")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Peru") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Lähetä") {
            if model.askForHelp(on: parent.id, title: title, helperID: helperID, day: hasDay ? Day(date: day) : nil, message: message) {
              dismiss()
            }
          }
          .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        helperID = model.partner?.id
        day = parent.prepDay?.date() ?? parent.eventDay?.date() ?? Date()
      }
    }
  }
}
