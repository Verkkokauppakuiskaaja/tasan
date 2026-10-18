import SwiftUI
import TasanCore

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var editingMember: Member?
  @State private var isAddingChild = false
  @State private var isConfirmingLeave = false
  @State private var googleError: String?
  @State private var appleEnabled = false
  @State private var googleEnabled = false
  @State private var shareTitles = DeviceSettings.shareBusyTitles

  var body: some View {
    let state = model.state
    NavigationStack {
      Form {
        if let family = state.family {
          Section("Perhe") {
            TextField("Perheen nimi", text: Binding(get: { family.name }, set: { var f = family; f.name = $0; model.save(f) }))
            ForEach(state.members) { member in
              Button {
                editingMember = member
              } label: {
                HStack {
                  MemberAvatar(member: member, size: 30)
                  VStack(alignment: .leading) {
                    Text(member.name).foregroundColor(AppColor.textPrimary)
                    Text(roleText(member)).font(.caption).foregroundColor(AppColor.textSecondary)
                  }
                }
              }
            }
            Button("Lisää lapsi", systemImage: "plus") { isAddingChild = true }
          }

          Section {
            Toggle(
              "Ylläpitäjä voi siirtää vastuun suoraan",
              isOn: Binding(get: { family.adminDirectTransferEnabled }, set: { var f = family; f.adminDirectTransferEnabled = $0; model.save(f) })
            )
            .disabled(!model.isAdmin)
          } header: {
            Text("Vastuun siirto")
          } footer: {
            Text("Oletuksena vastaanottaja hyväksyy aina siirron. Päällä ollessaan ylläpitäjä voi valita siirtävänsä suoraan; siirto näkyy silti molemmille ja historiaan.")
          }

          Section("Perhepalaveri") {
            Toggle("Viikkopalaverin muistutus", isOn: Binding(get: { family.weeklyMeeting.enabled }, set: { var f = family; f.weeklyMeeting.enabled = $0; model.save(f) }))
            if family.weeklyMeeting.enabled {
              Picker("Päivä", selection: Binding(get: { family.weeklyMeeting.weekday }, set: { var f = family; f.weeklyMeeting.weekday = $0; model.save(f) })) {
                ForEach(1...7, id: \.self) { Text(DateText.weekdayName($0).capitalized(with: .current)).tag($0) }
              }
              DatePicker(
                "Kello",
                selection: Binding(
                  get: { Day.today().date(minutes: family.weeklyMeeting.minutes) },
                  set: {
                    let parts = Calendar.finnish.dateComponents([.hour, .minute], from: $0)
                    var f = family
                    f.weeklyMeeting.minutes = (parts.hour ?? 19) * 60 + (parts.minute ?? 0)
                    model.save(f)
                  }
                ),
                displayedComponents: .hourAndMinute
              )
            }
            Toggle("Kuukausipalaveri (kuun viimeinen sunnuntai)", isOn: Binding(get: { family.monthlyMeetingEnabled }, set: { var f = family; f.monthlyMeetingEnabled = $0; model.save(f) }))
          }
        }

        Section {
          Toggle("Apple-kalenteri", isOn: $appleEnabled)
            .onChange(of: appleEnabled) { _, on in
              Task {
                if on, !model.calendars.apple.isAuthorized {
                  appleEnabled = await model.calendars.apple.requestAccess()
                }
                model.calendars.appleEnabled = appleEnabled
                model.calendarSettingsChanged()
              }
            }
          if model.calendars.google.isSignedIn {
            Toggle("Google-kalenteri (\(model.calendars.google.accountEmail ?? String(localized: "kirjautunut")))", isOn: $googleEnabled)
              .onChange(of: googleEnabled) { _, on in
                model.calendars.googleEnabled = on
                model.calendarSettingsChanged()
              }
            Button("Kirjaudu ulos Googlesta", role: .destructive) {
              model.calendars.googleEnabled = false
              googleEnabled = false
              model.calendarSettingsChanged()
              model.calendars.google.signOut()
            }
          } else {
            Button("Yhdistä Google-kalenteri") {
              Task {
                do {
                  try await model.calendars.google.signIn()
                  model.calendars.googleEnabled = true
                  googleEnabled = true
                  model.calendarSettingsChanged()
                } catch {
                  googleError = error.localizedDescription
                }
              }
            }
          }
          if let googleError {
            Text(googleError).font(.caption).foregroundColor(AppColor.error)
          }
          Toggle("Näytä menojeni nimet perheelle", isOn: $shareTitles)
            .onChange(of: shareTitles) { _, on in
              DeviceSettings.shareBusyTitles = on
              model.calendarSettingsChanged()
            }
        } header: {
          Text("Oma kalenteri")
        } footer: {
          Text("Lupa on henkilökohtainen: jokainen aikuinen yhdistää oman kalenterinsa omalla puhelimellaan. Tasan! kirjoittaa vain omaan Tasan!-kalenteriinsa ja lukee muita kalentereita päällekkäisyyksien ja perheen kalenterin vuoksi. Ilman nimiä toinen aikuinen näkee menosi vain merkinnällä Varattu.")
        }

        Section("Ilmoitukset") {
          Button("Salli muistutukset ja vastuupyynnöt") {
            Task { _ = await model.notifications.requestAuthorization() }
          }
        }

        Section {
          Button(model.isOwner ? String(localized: "Poista perhe ja lopeta jakaminen") : String(localized: "Poistu perheestä"), role: .destructive) {
            isConfirmingLeave = true
          }
        } footer: {
          Text(verbatim: "Tasan! \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        }
      }
      .navigationTitle("Asetukset")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Valmis") { dismiss() } }
      }
      .sheet(item: $editingMember) { MemberEditorView(member: $0, isNew: false) }
      .sheet(isPresented: $isAddingChild) {
        MemberEditorView(member: Member(name: "", colorHex: Member.palette[state.members.count % Member.palette.count], role: .child), isNew: true)
      }
      .confirmationDialog("Oletko varma?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
        Button(model.isOwner ? String(localized: "Poista perhe") : String(localized: "Poistu"), role: .destructive) {
          Task {
            await model.leaveFamily()
            dismiss()
          }
        }
      } message: {
        Text(model.isOwner ? String(localized: "Perheen tiedot poistetaan iCloudista molemmilta aikuisilta.") : String(localized: "Tiedot poistuvat tästä puhelimesta. Voit liittyä uudelleen kutsulla."))
      }
      .onAppear {
        appleEnabled = model.calendars.appleEnabled
        googleEnabled = model.calendars.googleEnabled
      }
    }
  }

  private func roleText(_ member: Member) -> String {
    switch member.role {
    case .adminAdult: return String(localized: "Aikuinen, ylläpitäjä")
    case .adult: return member.cloudUserID == nil ? String(localized: "Aikuinen, ei vielä liittynyt") : String(localized: "Aikuinen")
    case .child:
      return [member.schoolClass.map { String(localized: "\($0) lk", comment: "School class, e.g. 3 lk") }, member.school]
        .compactMap { $0 }.joined(separator: ", ").nonEmpty ?? String(localized: "Lapsi")
    case .teen: return String(localized: "Teini")
    case .helper: return String(localized: "Apulainen")
    }
  }
}

struct MemberEditorView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var member: Member
  @State private var hasBirthday: Bool
  @State private var birthday: Date
  @State private var hobbies: String
  @State private var isConfirmingDelete = false
  let isNew: Bool

  init(member: Member, isNew: Bool) {
    self.isNew = isNew
    _member = State(initialValue: member)
    _hasBirthday = State(initialValue: member.birthday != nil)
    _birthday = State(initialValue: member.birthday?.date() ?? Calendar.current.date(byAdding: .year, value: -6, to: Date())!)
    _hobbies = State(initialValue: member.hobbies.joined(separator: ", "))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Nimi", text: $member.name)
          ColorPickerRow(selection: $member.colorHex)
          Toggle("Syntymäpäivä", isOn: $hasBirthday)
          if hasBirthday {
            DatePicker("Päivä", selection: $birthday, displayedComponents: .date)
          }
        }
        if member.role == .child || member.role == .teen {
          Section {
            TextField("Vaatekoko, esim. 122", text: optional(\.clothingSize))
            TextField("Kenkäkoko, esim. 31", text: optional(\.shoeSize))
          } header: {
            Text("Koot")
          } footer: {
            Text("Vuosikello muistuttaa kokotarkistuksista ennen kausivaihtoja.")
          }
          Section("Koulu ja harrastukset") {
            TextField("Koulu tai päiväkoti", text: optional(\.school))
            TextField("Luokka tai ryhmä", text: optional(\.schoolClass))
            TextField("Harrastukset pilkulla erotettuna", text: $hobbies)
          }
        }
        if !isNew && member.id != model.meID && member.role != .adminAdult {
          Section {
            Button("Poista jäsen", role: .destructive) { isConfirmingDelete = true }
          }
        }
      }
      .navigationTitle(isNew ? String(localized: "Uusi lapsi") : member.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Peru") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Tallenna") {
            member.birthday = hasBirthday ? Day(date: birthday) : nil
            member.hobbies = hobbies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            model.save(member)
            model.refreshYearClock()
            dismiss()
          }
          .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .confirmationDialog("Poistetaanko \(member.name)?", isPresented: $isConfirmingDelete) {
        Button("Poista", role: .destructive) {
          model.delete(member)
          dismiss()
        }
      }
    }
  }

  private func optional(_ keyPath: WritableKeyPath<Member, String?>) -> Binding<String> {
    Binding(
      get: { member[keyPath: keyPath] ?? "" },
      set: { member[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
    )
  }
}

extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}
