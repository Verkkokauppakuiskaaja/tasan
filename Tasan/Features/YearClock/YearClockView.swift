import SwiftUI
import TasanCore

/*
 * "Vuosikello": what the year brings, month by month, and the
 * templates behind it. Every template can be switched off, edited
 * or added, and the tasks follow on their own.
 */
struct YearClockView: View {
  @Environment(AppModel.self) private var model
  @State private var mode: Mode = .months
  @State private var month = Day.today().month
  @State private var year = Day.today().year
  @State private var editing: YearTemplate?
  @State private var isAdding = false

  enum Mode: String, CaseIterable {
    case months = "Kuukaudet"
    case templates = "Mallit"
  }

  var body: some View {
    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
          TitleSection(title: "Vuosikello", subtitle: "Tehtävät syntyvät malleista ennen kuin kukaan muistaa niitä.")
          Picker("Näkymä", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)

          switch mode {
          case .months: months
          case .templates: templates
          }
        }
      }
      .navigationDestination(for: UUID.self) { TaskDetailView(taskID: $0) }
      .sheet(item: $editing) { TemplateEditorView(template: $0, isNew: false) }
      .sheet(isPresented: $isAdding) {
        TemplateEditorView(
          template: YearTemplate(areaKind: .holidays, title: "", rule: .fixed(month: month, day: 1), leadDays: 7),
          isNew: true
        )
      }
    }
  }

  // MARK: Months

  private var months: some View {
    let state = model.state
    let occurrences = YearClock().monthOverview(in: state, year: year, month: month)
    let tasksByKey = Dictionary(state.tasks.compactMap { task in task.occurrenceKey.map { ($0, task) } }, uniquingKeysWith: { first, _ in first })

    return VStack(alignment: .leading, spacing: AppSpacing.md) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: AppSpacing.xs) {
            ForEach(0..<12, id: \.self) { offset in
              let target = monthAt(offset: offset)
              let y = target.0
              let m = target.1
              Button {
                year = y
                month = m
              } label: {
                Text(FinnishCalendar.monthNames[m - 1])
                  .font(AppTypography.bodyMedium)
                  .padding(.horizontal, AppSpacing.md)
                  .padding(.vertical, AppSpacing.xs)
                  .foregroundColor(m == month && y == year ? .white : AppColor.textPrimary)
                  .background(Capsule().fill(m == month && y == year ? AppColor.primary : AppColor.card))
              }
              .buttonStyle(.plain)
              .id(offset)
            }
          }
        }
        .onAppear { proxy.scrollTo(0, anchor: .leading) }
      }

      if occurrences.isEmpty {
        EmptyState(systemImage: "leaf", title: "Hiljainen kuukausi", message: "Tälle kuukaudelle ei ole malleja. Lisää oma Mallit-välilehdeltä.")
      }

      ForEach(AreaKind.allCases, id: \.self) { kind in
        let items = occurrences.filter { $0.template.areaKind == kind }
        if !items.isEmpty {
          SectionHeader(title: kind.title)
          Card {
            ForEach(items, id: \.key) { occurrence in
              occurrenceRow(occurrence, task: tasksByKey[occurrence.key], state: state)
            }
          }
        }
      }
    }
  }

  private func occurrenceRow(_ occurrence: YearClock.Occurrence, task: FamilyTask?, state: FamilyState) -> some View {
    let title = occurrence.template.title + (state.member(occurrence.memberID).map { ": \($0.name)" } ?? "")
    let area = YearClock.area(for: occurrence.template.areaKind, subject: occurrence.memberID, in: state)
    return HStack(spacing: AppSpacing.sm) {
      VStack(alignment: .center, spacing: 0) {
        Text("\(occurrence.eventDay.day)").font(AppTypography.headline)
        Text(FinnishCalendar.weekdayShortNames[occurrence.eventDay.isoWeekday() - 1]).font(AppTypography.caption)
      }
      .frame(width: 36)
      .foregroundColor(occurrence.template.areaKind.color)

      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(AppTypography.bodyMedium)
        Text("Valmistelu \(occurrence.template.leadDays) pv ennen")
          .font(AppTypography.caption)
          .foregroundColor(AppColor.textSecondary)
      }
      Spacer()
      if let task {
        NavigationLink(value: task.id) {
          HStack(spacing: 4) {
            MemberAvatar(member: state.member(task.responsibleID), size: 24)
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "chevron.right")
              .foregroundColor(task.status == .done ? AppColor.success : AppColor.textSecondary)
          }
        }
      } else {
        MemberAvatar(member: state.member(area?.ownerID), size: 24)
          .opacity(0.5)
      }
    }
  }

  private func monthAt(offset: Int) -> (Int, Int) {
    let today = Day.today()
    let total = today.month - 1 + offset
    return (today.year + total / 12, total % 12 + 1)
  }

  // MARK: Templates

  private var templates: some View {
    let state = model.state
    return VStack(alignment: .leading, spacing: AppSpacing.md) {
      ForEach(AreaKind.allCases, id: \.self) { kind in
        let area = state.areas.first { $0.kind == kind && $0.subjectMemberID == nil }
        let items = state.templates.filter { $0.areaKind == kind }.sorted { $0.title < $1.title }
        SectionHeader(title: kind.title, subtitle: area?.enabled == false ? "Pois käytöstä" : nil)
        Card {
          if let area {
            Toggle("Osa-alue käytössä", isOn: Binding(get: { area.enabled }, set: { var a = area; a.enabled = $0; model.save(a) }))
              .font(AppTypography.bodyMedium)
            Divider()
          }
          ForEach(items) { template in
            HStack {
              Button {
                editing = template
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(template.title).font(AppTypography.body).foregroundColor(AppColor.textPrimary)
                  Text("\(template.rule.finnishDescription) · valmistelu \(template.leadDays) pv\(template.scope == .perChild ? " · jokaiselle lapselle" : "")")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColor.textSecondary)
                }
              }
              .buttonStyle(.plain)
              Spacer()
              Toggle("", isOn: Binding(get: { template.enabled }, set: { var t = template; t.enabled = $0; model.save(t); model.refreshYearClock() }))
                .labelsHidden()
            }
          }
        }
      }
      SecondaryButton(title: "Lisää oma malli", systemImage: "plus") { isAdding = true }

      if let family = state.family {
        SectionHeader(title: "Koulun lomat")
        Card {
          Stepper(
            "Hiihtoloma viikolla \(family.winterHolidayWeek)",
            value: Binding(get: { family.winterHolidayWeek }, set: { var f = family; f.winterHolidayWeek = $0; model.save(f) }),
            in: 7...11
          )
          Text("Hiihtoloman viikko vaihtelee kunnittain (viikot 8–10). Syysloma on mallissa viikolla 42.")
            .font(AppTypography.caption)
            .foregroundColor(AppColor.textSecondary)
        }
      }
    }
  }
}

/// Edit one template's title, date rule and preparation time.
struct TemplateEditorView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var template: YearTemplate
  @State private var ruleKind: RuleKind
  @State private var month: Int
  @State private var dayOfMonth: Int
  @State private var weekday: Int
  @State private var nth: Int
  @State private var offset: Int
  @State private var week: Int
  @State private var isConfirmingDelete = false
  let isNew: Bool

  enum RuleKind: String, CaseIterable {
    case fixed = "Päivämäärä"
    case nthWeekday = "Viikonpäivä kuukaudessa"
    case isoWeek = "Viikko"
    case easter = "Pääsiäisestä"
    case birthday = "Syntymäpäivästä"
    case winterHoliday = "Hiihtoloma"
    case midsummerEve = "Juhannusaatto"
  }

  init(template: YearTemplate, isNew: Bool) {
    self.isNew = isNew
    _template = State(initialValue: template)
    var kind = RuleKind.fixed, month = 1, day = 1, weekday = 7, nth = 1, offset = 0, week = 42
    switch template.rule {
    case let .fixed(m, d): kind = .fixed; month = m; day = d
    case let .nthWeekday(m, w, n): kind = .nthWeekday; month = m; weekday = w; nth = n
    case let .easter(o): kind = .easter; offset = o
    case let .isoWeek(wk, w): kind = .isoWeek; week = wk; weekday = w
    case .winterHoliday: kind = .winterHoliday
    case .midsummerEve: kind = .midsummerEve
    case let .birthday(o): kind = .birthday; offset = o
    }
    _ruleKind = State(initialValue: kind)
    _month = State(initialValue: month)
    _dayOfMonth = State(initialValue: day)
    _weekday = State(initialValue: weekday)
    _nth = State(initialValue: nth)
    _offset = State(initialValue: offset)
    _week = State(initialValue: week)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Otsikko", text: $template.title)
          Picker("Osa-alue", selection: $template.areaKind) {
            ForEach(AreaKind.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          TextField("Muistiinpanot", text: Binding(get: { template.notes ?? "" }, set: { template.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
        }
        Section("Milloin") {
          Picker("Sääntö", selection: $ruleKind) {
            ForEach(RuleKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          switch ruleKind {
          case .fixed:
            Picker("Kuukausi", selection: $month) { monthOptions }
            Stepper("Päivä \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
          case .nthWeekday:
            Picker("Kuukausi", selection: $month) { monthOptions }
            Picker("Viikonpäivä", selection: $weekday) { weekdayOptions }
            Picker("Kuinka mones", selection: $nth) {
              ForEach(1...4, id: \.self) { Text("\($0).").tag($0) }
              Text("Viimeinen").tag(-1)
            }
          case .isoWeek:
            Stepper("Viikko \(week)", value: $week, in: 1...53)
            Picker("Viikonpäivä", selection: $weekday) { weekdayOptions }
          case .easter, .birthday:
            Stepper(offsetText, value: $offset, in: -60...60)
          case .winterHoliday, .midsummerEve:
            EmptyView()
          }
        }
        Section {
          Stepper("Valmistelu \(template.leadDays) pv ennen", value: $template.leadDays, in: 0...90)
          if ruleKind != .birthday {
            Toggle("Oma tehtävä jokaiselle lapselle", isOn: Binding(get: { template.scope == .perChild }, set: { template.scope = $0 ? .perChild : .family }))
          }
        } footer: {
          Text("Tehtävä syntyy, kun valmistelupäivä lähestyy, ja menee osa-alueen omistajalle.")
        }
        if !isNew {
          Section {
            Button("Poista malli", role: .destructive) { isConfirmingDelete = true }
          }
        }
      }
      .navigationTitle(isNew ? "Uusi malli" : "Muokkaa mallia")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Peru") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Tallenna") {
            template.rule = rule
            if template.rule.isPerMember { template.scope = .perChild }
            model.save(template)
            model.refreshYearClock()
            dismiss()
          }
          .disabled(template.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .confirmationDialog("Poistetaanko malli?", isPresented: $isConfirmingDelete) {
        Button("Poista", role: .destructive) {
          model.delete(template)
          dismiss()
        }
      } message: {
        Text("Jo luodut tehtävät jäävät. Voit myös vain kytkeä mallin pois päältä.")
      }
    }
  }

  private var rule: YearRule {
    switch ruleKind {
    case .fixed: return .fixed(month: month, day: dayOfMonth)
    case .nthWeekday: return .nthWeekday(month: month, weekday: weekday, n: nth)
    case .isoWeek: return .isoWeek(week: week, weekday: weekday)
    case .easter: return .easter(offset: offset)
    case .birthday: return .birthday(offset: offset)
    case .winterHoliday: return .winterHoliday
    case .midsummerEve: return .midsummerEve
    }
  }

  private var offsetText: String {
    if offset == 0 { return ruleKind == .easter ? "Pääsiäispäivä" : "Syntymäpäivä" }
    if offset < 0 { return "\(-offset) pv ennen \(ruleKind == .easter ? "pääsiäistä" : "syntymäpäivää")" }
    return "\(offset) pv \(ruleKind == .easter ? "pääsiäisen" : "syntymäpäivän") jälkeen"
  }

  private var monthOptions: some View {
    ForEach(1...12, id: \.self) { Text(FinnishCalendar.monthNames[$0 - 1]).tag($0) }
  }

  private var weekdayOptions: some View {
    ForEach(1...7, id: \.self) { Text(FinnishCalendar.weekdayNames[$0 - 1]).tag($0) }
  }
}
