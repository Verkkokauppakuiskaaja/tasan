import CloudKit
import SwiftUI
import TasanCore
import UIKit

struct TodayView: View {
  @Environment(AppModel.self) private var model
  @State private var path: [UUID] = []
  @State private var scope: Scope = .mine
  @State private var isAddingTask = false
  @State private var isImporting = false
  @State private var isShowingSettings = false

  enum Scope: CaseIterable {
    case mine
    case all

    var title: LocalizedStringKey {
      switch self {
      case .mine: return "Minun"
      case .all: return "Kaikki"
      }
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          header

          if model.partner?.cloudUserID == nil && model.isOwner {
            InviteCard()
          }

          ForEach(model.requestsToMe) { request in
            TransferRequestCard(request: request)
          }

          ForEach(myOverlaps) { overlap in
            OverlapCard(overlap: overlap)
          }

          Picker("Näytä", selection: $scope) {
            ForEach(Scope.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)

          taskSections
        }
      }
      .navigationDestination(for: UUID.self) { TaskDetailView(taskID: $0) }
      .sheet(isPresented: $isAddingTask) { TaskEditorView(task: nil) }
      .sheet(isPresented: $isImporting) { ImageImportView() }
      .sheet(isPresented: $isShowingSettings) { SettingsView() }
      .onChange(of: model.openedTaskID) { _, id in
        guard let id else { return }
        path = [id]
        model.openedTaskID = nil
      }
      .refreshable { await model.sync.syncNow() }
    }
  }

  private var header: some View {
    HStack(spacing: AppSpacing.sm) {
      VStack(alignment: .leading, spacing: 0) {
        Wordmark(fontSize: 30)
        Text("Hei \(model.me?.name ?? "")! \(Day.today().relativeText().capitalized) \(DateText.dayMonth(Day.today()))")
          .font(AppTypography.caption)
          .foregroundColor(AppColor.textSecondary)
      }
      Spacer()
      CircleIconButton(systemName: "camera.viewfinder", accessibilityLabel: String(localized: "Kuvasta tapahtumaksi")) { isImporting = true }
      CircleIconButton(systemName: "plus", accessibilityLabel: String(localized: "Uusi tehtävä")) { isAddingTask = true }
      CircleIconButton(systemName: "gearshape", accessibilityLabel: String(localized: "Asetukset")) { isShowingSettings = true }
    }
  }

  private var myOverlaps: [Overlap] {
    model.overlaps.filter { $0.memberID == model.meID }
  }

  private var visibleTasks: [FamilyTask] {
    let open = model.state.tasks.filter { $0.status == .open }
    let list = scope == .mine ? open.filter { $0.responsibleID == model.meID } : open.filter { $0.responsibleID != nil }
    return list.sorted { ($0.actionDay ?? .distant) < ($1.actionDay ?? .distant) }
  }

  @ViewBuilder
  private var taskSections: some View {
    let today = Day.today()
    let weekEnd = today.adding(days: 7)
    let tasks = visibleTasks
    let now = tasks.filter { ($0.actionDay ?? .distant) <= today }
    let week = tasks.filter { let day = $0.actionDay ?? .distant; return day > today && day <= weekEnd }
    let later = tasks.filter { ($0.actionDay ?? .distant) > weekEnd }

    if tasks.isEmpty && model.openTasks.isEmpty {
      EmptyState(
        systemImage: "sparkles",
        title: String(localized: "Ei mitään juuri nyt"),
        message: String(localized: "Vuosikello lisää tehtävät ajoissa. Voit myös lisätä tehtävän itse tai kuvasta.")
      )
    }

    section(String(localized: "Tänään ja myöhässä"), now)
    section(String(localized: "Seuraavat 7 päivää"), week)

    if !model.openTasks.isEmpty {
      SectionHeader(title: String(localized: "Avoimet"), subtitle: String(localized: "Kuka tahansa voi ottaa"), count: model.openTasks.count)
      Card {
        ForEach(model.openTasks) { task in
          HStack {
            NavigationLink(value: task.id) { TaskRow(task: task, showsResponsible: false) }
              .buttonStyle(.plain)
            Button("Ota") { model.take(task.id) }
              .font(AppTypography.headline)
              .buttonStyle(.borderedProminent)
              .tint(AppColor.success)
          }
          if task.id != model.openTasks.last?.id { Divider() }
        }
      }
    }

    section(String(localized: "Myöhemmin"), later)
  }

  @ViewBuilder
  private func section(_ title: String, _ tasks: [FamilyTask]) -> some View {
    if !tasks.isEmpty {
      SectionHeader(title: title, count: nil)
      Card {
        ForEach(tasks) { task in
          NavigationLink(value: task.id) {
            TaskRow(task: task, showsResponsible: scope == .all)
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("Merkitse hoidetuksi", systemImage: "checkmark.circle") { model.complete(task.id) }
          }
          if task.id != tasks.last?.id { Divider() }
        }
      }
    }
  }
}

// MARK: - Cards

struct TransferRequestCard: View {
  @Environment(AppModel.self) private var model
  let request: TransferRequest
  @State private var isDeclining = false
  @State private var reason = ""

  var body: some View {
    let state = model.state
    let from = state.member(request.requestedByID)
    Card {
      HStack(spacing: AppSpacing.sm) {
        MemberAvatar(member: from, size: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(from?.name ?? String(localized: "Perheenjäsen")) pyytää sinua ottamaan")
            .font(AppTypography.caption)
            .foregroundColor(AppColor.textSecondary)
          Text(state.subjectTitle(request.subject))
            .font(AppTypography.headline)
            .foregroundColor(AppColor.textPrimary)
        }
      }
      if let message = request.message {
        Text("”\(message)”", comment: "A quoted message")
          .font(AppTypography.body)
          .foregroundColor(AppColor.textPrimary)
      }
      if let day = request.returnDay {
        Pill(text: String(localized: "Väliaikainen, palaa \(day.relativeText())"), systemImage: "arrow.uturn.backward", color: AppColor.detail)
      }
      if case let .task(id) = request.subject, let task = state.task(id), let time = task.timeText() {
        Text(time).font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
      }
      HStack(spacing: AppSpacing.sm) {
        PrimaryButton(title: String(localized: "Hyväksy"), systemImage: "checkmark") { model.acceptTransfer(request.id) }
        SecondaryButton(title: String(localized: "Kieltäydy")) { isDeclining = true }
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        .stroke(AppColor.secondary, lineWidth: 2)
    )
    .alert("Kieltäydy", isPresented: $isDeclining) {
      TextField("Syy (vapaaehtoinen)", text: $reason)
      Button("Kieltäydy", role: .destructive) { model.declineTransfer(request.id, reason: reason) }
      Button("Peru", role: .cancel) {}
    } message: {
      Text("Vastuu pysyy ennallaan ja \(model.state.member(request.requestedByID)?.name ?? String(localized: "lähettäjä")) saa tiedon.")
    }
  }
}

struct OverlapCard: View {
  @Environment(AppModel.self) private var model
  let overlap: Overlap

  var body: some View {
    let state = model.state
    Card {
      Label("Päällekkäisyys", systemImage: "exclamationmark.triangle.fill")
        .font(AppTypography.caption.weight(.semibold))
        .foregroundColor(AppColor.detail)
      Text(state.task(overlap.taskID).map(state.displayTitle(of:)) ?? "")
        .font(AppTypography.headline)
      Group {
        if let conflict = overlap.conflictingTitle {
          Text("Sinulla on samaan aikaan ”\(conflict)”.")
        } else {
          Text("Sinulla on samaan aikaan muuta kalenterissa.")
        }
      }
        .font(AppTypography.body)
        .foregroundColor(AppColor.textSecondary)
      if let suggested = state.member(overlap.suggestedMemberID) {
        SecondaryButton(title: String(localized: "Ehdota siirtoa: \(suggested.name)"), systemImage: "arrow.left.arrow.right") {
          model.requestTransfer(.task(overlap.taskID), to: suggested.id, message: String(localized: "Mulla on samaan aikaan muuta, voitko ottaa?"), returnDay: nil, direct: false)
        }
      }
    }
  }
}

struct InviteCard: View {
  @Environment(AppModel.self) private var model
  @State private var share: CKShare?
  @State private var isLoading = false

  var body: some View {
    Card {
      Text("Kutsu toinen aikuinen")
        .font(AppTypography.headline)
      Text("Tasan! toimii, kun molemmat näkevät saman listan. Kutsu lähtee iCloudin kautta viestinä, sähköpostina tai linkkinä.")
        .font(AppTypography.body)
        .foregroundColor(AppColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      PrimaryButton(title: isLoading ? String(localized: "Valmistellaan…") : String(localized: "Kutsu"), systemImage: "person.badge.plus") {
        isLoading = true
        Task {
          do {
            share = try await model.invitationShare()
          } catch {
            model.errorMessage = String(localized: "Kutsua ei voitu luoda: \(error.localizedDescription). Tarkista, että olet kirjautunut iCloudiin.")
          }
          isLoading = false
        }
      }
      .disabled(isLoading)
    }
    .sheet(item: Binding(get: { share.map(IdentifiedShare.init) }, set: { share = $0?.share })) { item in
      CloudSharingView(share: item.share, container: model.sync.container)
        .ignoresSafeArea()
    }
  }
}

struct IdentifiedShare: Identifiable {
  let share: CKShare
  var id: String { share.recordID.recordName }
}

/// UIKit's iCloud sharing sheet: invite people and manage who has access.
struct CloudSharingView: UIViewControllerRepresentable {
  let share: CKShare
  let container: CKContainer

  func makeUIViewController(context: Context) -> UICloudSharingController {
    let controller = UICloudSharingController(share: share, container: container)
    controller.availablePermissions = [.allowPrivate, .allowReadWrite]
    controller.modalPresentationStyle = .formSheet
    return controller
  }

  func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}
