import SwiftUI
import TasanCore

/// The invited adult opened the link: pick your own profile, or add yourself.
struct JoinFamilyView: View {
  @Environment(AppModel.self) private var model
  @State private var newName = ""
  @State private var color = Member.palette[1]

  private var unclaimedAdults: [Member] {
    model.state.adults.filter { $0.cloudUserID == nil }
  }

  var body: some View {
    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
          Wordmark(fontSize: 40)
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xl)

          if model.state.family == nil {
            VStack(spacing: AppSpacing.md) {
              ProgressView()
              Text("Haetaan perheen tietoja iCloudista…")
                .font(AppTypography.body)
                .foregroundColor(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xxl)
          } else {
            TitleSection(
              title: String(localized: "Tervetuloa perheeseen \(model.state.family?.name ?? "")"),
              subtitle: String(localized: "Kuka sinä olet? Valitse oma profiilisi tai lisää itsesi.")
            )

            ForEach(unclaimedAdults) { adult in
              Button {
                model.claim(adult.id)
              } label: {
                HStack(spacing: AppSpacing.md) {
                  MemberAvatar(member: adult, size: 44)
                  Text("Olen \(adult.name)")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColor.textPrimary)
                  Spacer()
                  Image(systemName: "chevron.right").foregroundColor(AppColor.textSecondary)
                }
                .padding(AppSpacing.md)
                .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous).fill(AppColor.card))
              }
              .buttonStyle(.plain)
            }

            Card {
              LabeledField("Uusi aikuinen", text: $newName, prompt: "Sinun nimesi")
              ColorPickerRow(selection: $color)
              PrimaryButton(title: String(localized: "Lisää minut"), systemImage: "person.badge.plus") {
                model.claim(nil, newName: newName.trimmingCharacters(in: .whitespaces), color: color)
              }
              .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
          }
        }
      }
    }
  }
}
