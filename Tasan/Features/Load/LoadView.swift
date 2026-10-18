import SwiftUI
import TasanCore

/*
 * "Jakonäkymä": who carries what right now. Counts, not points:
 * the aim is to make the load visible so it can be evened out
 * together, area by area.
 */
struct LoadView: View {
  @Environment(AppModel.self) private var model
  @State private var transferringArea: UUID?
  @State private var isAddingArea = false

  var body: some View {
    let state = model.state
    let summary = LoadSummary.make(from: state, today: .today())

    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          TitleSection(title: "Kuka kantaa mitäkin", subtitle: "Avoimet vastuut nyt. Tasataan yhdessä, ei lasketa pisteitä.")

          shareBar(summary, state)

          ForEach(summary.rows) { row in
            memberCard(row, state)
          }

          if summary.openForTaking > 0 {
            Card {
              Label("\(summary.openForTaking) avointa tehtävää odottaa ottajaa", systemImage: "hand.raised.fill")
                .font(AppTypography.headline)
                .foregroundColor(AppColor.success)
            }
          }

          SectionHeader(title: "Osa-alueet", subtitle: "Uudet tehtävät menevät omistajalle")
          Card {
            ForEach(state.areas.filter(\.enabled)) { area in
              areaRow(area, state)
              if area.id != state.areas.filter(\.enabled).last?.id { Divider() }
            }
          }
          SecondaryButton(title: "Lisää osa-alue, esim. Liisan harrastukset", systemImage: "plus") { isAddingArea = true }
        }
      }
      .navigationDestination(for: UUID.self) { TaskDetailView(taskID: $0) }
      .sheet(item: Binding(get: { transferringArea.map(IdentifiedID.init) }, set: { transferringArea = $0?.id })) { item in
        TransferSheet(subject: .area(item.id))
      }
      .sheet(isPresented: $isAddingArea) { AreaEditorView() }
    }
  }

  private func shareBar(_ summary: LoadSummary, _ state: FamilyState) -> some View {
    let total = max(summary.rows.reduce(0) { $0 + $1.openTasks }, 1)
    return Card {
      GeometryReader { geometry in
        HStack(spacing: 2) {
          ForEach(summary.rows) { row in
            let member = state.member(row.memberID)
            Rectangle()
              .fill(member.map { Color(hexString: $0.colorHex) } ?? AppColor.border)
              .frame(width: max(geometry.size.width * CGFloat(row.openTasks) / CGFloat(total) - 2, row.openTasks > 0 ? 4 : 0))
          }
        }
        .clipShape(Capsule())
      }
      .frame(height: 14)
      HStack {
        ForEach(summary.rows) { row in
          if let member = state.member(row.memberID) {
            Text("\(member.name) \(Int((summary.share(of: member.id) * 100).rounded())) %")
              .font(AppTypography.caption.weight(.semibold))
              .foregroundColor(Color(hexString: member.colorHex))
            Spacer()
          }
        }
      }
    }
  }

  private func memberCard(_ row: LoadSummary.Row, _ state: FamilyState) -> some View {
    let member = state.member(row.memberID)
    return Card {
      HStack(spacing: AppSpacing.sm) {
        MemberAvatar(member: member, size: 44)
        VStack(alignment: .leading, spacing: 2) {
          Text(member?.name ?? "").font(AppTypography.headline)
          Text("\(row.openTasks) avointa · \(row.upcomingTasks) seuraavan 2 viikon aikana · \(row.completedInPeriod) hoidettu 30 pv")
            .font(AppTypography.caption)
            .foregroundColor(AppColor.textSecondary)
        }
      }
      let areas = state.areas.filter { $0.enabled }
      FlowRow {
        ForEach(areas) { area in
          let count = row.tasksByArea[area.id] ?? 0
          if count > 0 || area.ownerID == row.memberID {
            Pill(
              text: "\(area.name) \(count)\(area.ownerID == row.memberID ? " ★" : "")",
              systemImage: area.kind.symbolName,
              color: area.kind.color
            )
          }
        }
      }
      let tasks = state.tasks
        .filter { $0.status == .open && $0.responsibleID == row.memberID }
        .sorted { ($0.actionDay ?? .distant) < ($1.actionDay ?? .distant) }
        .prefix(4)
      ForEach(Array(tasks)) { task in
        NavigationLink(value: task.id) { TaskRow(task: task, showsResponsible: false) }.buttonStyle(.plain)
      }
    }
  }

  private func areaRow(_ area: Area, _ state: FamilyState) -> some View {
    HStack(spacing: AppSpacing.sm) {
      Image(systemName: area.kind.symbolName)
        .foregroundColor(area.kind.color)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(area.name).font(AppTypography.bodyMedium)
        if let pending = state.pendingTransfer(for: .area(area.id)) {
          Text("Odottaa: \(state.member(pending.toID)?.name ?? "")").font(AppTypography.caption).foregroundColor(AppColor.detail)
        }
      }
      Spacer()
      MemberAvatar(member: state.member(area.ownerID), size: 28)
      if model.meID.map({ state.canTransfer(.area(area.id), actorID: $0) }) == true, state.pendingTransfer(for: .area(area.id)) == nil {
        Button("Siirrä") { transferringArea = area.id }
          .font(AppTypography.caption.weight(.semibold))
          .buttonStyle(.bordered)
      }
    }
  }
}

struct IdentifiedID: Identifiable {
  let id: UUID
}

/// Wraps pills onto as many lines as needed.
struct FlowRow: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > width, x > 0 {
        x = 0
        y += lineHeight + spacing
        lineHeight = 0
      }
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: width == .infinity ? x : width, height: y + lineHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var lineHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += lineHeight + spacing
        lineHeight = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}

/// New or edited area, e.g. one narrowed to a single child.
struct AreaEditorView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var kind: AreaKind = .hobbies
  @State private var name = ""
  @State private var subjectID: UUID?
  @State private var ownerID: UUID?

  var body: some View {
    let state = model.state
    NavigationStack {
      Form {
        Picker("Tyyppi", selection: $kind) {
          ForEach(AreaKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbolName).tag($0) }
        }
        Picker("Lapsi", selection: $subjectID) {
          Text("Koko perhe").tag(UUID?.none)
          ForEach(state.children) { Text($0.name).tag(UUID?.some($0.id)) }
        }
        TextField("Nimi", text: $name)
        Picker("Omistaja", selection: $ownerID) {
          Text("Ei kukaan vielä").tag(UUID?.none)
          ForEach(state.responsibleCandidates) { Text($0.name).tag(UUID?.some($0.id)) }
        }
      }
      .navigationTitle("Uusi osa-alue")
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: subjectID) { _, _ in suggestName(state) }
      .onChange(of: kind) { _, _ in suggestName(state) }
      .onAppear {
        ownerID = model.meID
        suggestName(state)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Peru") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Tallenna") {
            model.save(Area(kind: kind, name: name, ownerID: ownerID, subjectMemberID: subjectID))
            dismiss()
          }
          .disabled(name.isEmpty)
        }
      }
    }
  }

  private func suggestName(_ state: FamilyState) {
    if let child = state.member(subjectID) {
      name = "\(child.name): \(kind.title.lowercased())"
    } else {
      name = kind.title
    }
  }
}
