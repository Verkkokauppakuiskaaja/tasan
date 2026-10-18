import SwiftUI
import TasanCore

/*
 * First launch on the adult who creates the family: who you are,
 * the children, which areas the year clock covers. The other adult
 * is invited from the Today screen once the family exists.
 */
struct OnboardingView: View {
  @Environment(AppModel.self) private var model

  private enum Step: Int, CaseIterable {
    case welcome, you, children, areas
  }

  @State private var step: Step = .welcome
  @State private var familyName = ""
  @State private var myName = ""
  @State private var myColor = Member.palette[0]
  @State private var children: [AppModel.NewChild] = [AppModel.NewChild(name: "", birthday: nil)]
  @State private var areas = Set(AreaKind.allCases)
  @State private var isCreating = false

  var body: some View {
    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
          switch step {
          case .welcome: welcome
          case .you: you
          case .children: childrenStep
          case .areas: areasStep
          }
        }
        .animation(.default, value: step)
      }
      .safeAreaInset(edge: .bottom) { footer }
    }
  }

  // MARK: Steps

  private var welcome: some View {
    VStack(spacing: AppSpacing.lg) {
      Spacer(minLength: AppSpacing.xxl)
      Wordmark(fontSize: 52)
      Tagline()
      Text("Kukaan ei kanna perheen muistilistaa yksin päässään. Tasan! muistuttaa ajoissa, näyttää kuka hoitaa mitäkin ja antaa vaihtaa vastuun kitkattomasti.")
        .font(AppTypography.body)
        .foregroundColor(AppColor.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: AppSpacing.sm) {
        feature("clock.arrow.circlepath", "Suomalainen vuosikello", "Kausivaatteet, lomat, synttärit ja juhlapyhät ajoissa.", AppColor.primary)
        feature("arrow.left.arrow.right", "Vastuun vaihto", "Siirrä vastuu, pyydä apua tai anna tehtävä avoimeksi.", AppColor.detail)
        feature("person.2.fill", "Kuorma näkyväksi", "Jakonäkymä ja perhepalaveri auttavat tasaamaan.", AppColor.success)
      }
      .padding(.top, AppSpacing.md)
    }
    .frame(maxWidth: .infinity)
  }

  private func feature(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey, _ color: Color) -> some View {
    HStack(spacing: AppSpacing.md) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(color)
        .frame(width: 48, height: 48)
        .background(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous).fill(color.opacity(0.12)))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(AppTypography.headline).foregroundColor(AppColor.textPrimary)
        Text(text).font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
      }
      Spacer()
    }
    .padding(AppSpacing.sm)
    .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous).fill(AppColor.card))
  }

  private var you: some View {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
      TitleSection(title: String(localized: "Perhe ja sinä"), subtitle: String(localized: "Sinusta tulee perheen ylläpitäjä. Toisen aikuisen kutsut seuraavaksi."))
      Card {
        LabeledField("Perheen nimi", text: $familyName, prompt: "esim. Virtaset")
        LabeledField("Sinun nimesi", text: $myName, prompt: "esim. Anna")
        Text("Väri").font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
        ColorPickerRow(selection: $myColor)
      }
    }
  }

  private var childrenStep: some View {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
      TitleSection(title: String(localized: "Lapset"), subtitle: String(localized: "Syntymäpäivistä vuosikello tekee synttäritehtävät. Koot, koulun ja harrastukset voit lisätä myöhemmin."))
      ForEach(children.indices, id: \.self) { index in
        Card {
          LabeledField("Nimi", text: $children[index].name, prompt: "esim. Liisa")
          DatePicker(
            "Syntymäpäivä",
            selection: Binding(
              get: { children[index].birthday ?? Calendar.current.date(byAdding: .year, value: -5, to: Date())! },
              set: { children[index].birthday = $0 }
            ),
            displayedComponents: .date
          )
        }
      }
      SecondaryButton(title: String(localized: "Lisää lapsi"), systemImage: "plus") {
        children.append(AppModel.NewChild(name: "", birthday: nil))
      }
    }
  }

  private var areasStep: some View {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
      TitleSection(title: String(localized: "Osa-alueet"), subtitle: String(localized: "Valitse, mistä vuosikello muistuttaa. Mallit voi muokata myöhemmin."))
      ForEach(AreaKind.allCases, id: \.self) { kind in
        Button {
          if areas.contains(kind) { areas.remove(kind) } else { areas.insert(kind) }
        } label: {
          HStack(spacing: AppSpacing.md) {
            Image(systemName: kind.symbolName)
              .foregroundColor(kind.color)
              .frame(width: 40, height: 40)
              .background(Circle().fill(kind.color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
              Text(kind.title).font(AppTypography.headline).foregroundColor(AppColor.textPrimary)
              Text(BuiltInTemplates.all().filter { $0.areaKind == kind }.prefix(3).map(\.displayTitle).joined(separator: ", "))
                .font(AppTypography.caption)
                .foregroundColor(AppColor.textSecondary)
                .lineLimit(2)
            }
            Spacer()
            Image(systemName: areas.contains(kind) ? "checkmark.circle.fill" : "circle")
              .font(.title2)
              .foregroundColor(areas.contains(kind) ? AppColor.primary : AppColor.textSecondary)
          }
          .padding(AppSpacing.md)
          .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous).fill(AppColor.card))
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: Footer

  private var footer: some View {
    VStack(spacing: AppSpacing.sm) {
      PrimaryButton(title: step == .areas ? String(localized: "Luo perhe") : String(localized: "Jatka"), systemImage: step == .areas ? "checkmark" : nil) {
        advance()
      }
      .disabled(!canAdvance || isCreating)
      if step != .welcome {
        Button("Takaisin") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
          .font(AppTypography.bodyMedium)
          .foregroundColor(AppColor.primaryForeground)
      }
    }
    .padding(.horizontal, AppSpacing.lg)
    .padding(.bottom, AppSpacing.sm)
    .background(AppColor.background)
  }

  private var canAdvance: Bool {
    switch step {
    case .you: return !familyName.trimmingCharacters(in: .whitespaces).isEmpty && !myName.trimmingCharacters(in: .whitespaces).isEmpty
    case .areas: return !areas.isEmpty
    default: return true
    }
  }

  private func advance() {
    if let next = Step(rawValue: step.rawValue + 1) {
      step = next
      return
    }
    isCreating = true
    Task {
      await model.createFamily(name: familyName, myName: myName, myColor: myColor, children: children, enabledAreas: areas)
      isCreating = false
    }
  }
}

/// Text field with a small caption above it, as in CalendropAI's forms.
struct LabeledField: View {
  let label: LocalizedStringKey
  @Binding var text: String
  var prompt: LocalizedStringKey = ""
  var axis: Axis = .horizontal

  init(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey = "", axis: Axis = .horizontal) {
    self.label = label
    self._text = text
    self.prompt = prompt
    self.axis = axis
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
      Text(label)
        .font(AppTypography.caption)
        .foregroundColor(AppColor.textSecondary)
      TextField(prompt, text: $text, axis: axis)
        .font(AppTypography.body)
        .padding(AppSpacing.sm)
        .background(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous).fill(AppColor.background))
    }
  }
}

struct ColorPickerRow: View {
  @Binding var selection: String

  var body: some View {
    HStack(spacing: AppSpacing.sm) {
      ForEach(Member.palette, id: \.self) { hex in
        Button {
          selection = hex
        } label: {
          Circle()
            .fill(Color(hexString: hex))
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(AppColor.textPrimary, lineWidth: selection == hex ? 3 : 0).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Väri \(hex)"))
      }
    }
  }
}
