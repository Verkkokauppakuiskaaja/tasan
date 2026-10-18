import PhotosUI
import SwiftUI
import TasanCore

/*
 * "Kuvasta tapahtumaksi": photograph a school bulletin or a party
 * invitation and get the event, with a preparation day, as a task.
 * On-device OCR, then Tasan!'s own Claude service.
 */
struct ImageImportView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var image: UIImage?
  @State private var photoItem: PhotosPickerItem?
  @State private var isShowingCamera = false
  @State private var isShowingConsent = !DeviceSettings.aiConsentAccepted
  @State private var isProcessing = false
  @State private var events: [ImportedEvent] = []
  @State private var errorText: String?
  @State private var selected: ImportedEvent?

  private let service = EventExtractionService()

  var body: some View {
    NavigationStack {
      Screen {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
          TitleSection(title: "Kuvasta tapahtumaksi", subtitle: "Koulun tiedote, synttärikutsu tai kuvakaappaus. Tasan! poimii tapahtuman ja valmistelun.")

          if let image {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 280)
              .frame(maxWidth: .infinity)
              .clipShape(RoundedRectangle(cornerRadius: AppRadius.image, style: .continuous))
              .overlay {
                if isProcessing { ProcessingOverlay(message: "Luetaan kuvaa ja etsitään tapahtumia…") }
              }
          }

          if UIImagePickerController.isSourceTypeAvailable(.camera) {
            ActionCard(title: "Ota kuva", subtitle: "Kuvaa tiedote tai kutsu", icon: "camera.fill", color: AppColor.primary) {
              isShowingCamera = true
            }
            .disabled(isProcessing)
          }
          PhotosPicker(selection: $photoItem, matching: .images) {
            HStack(spacing: AppSpacing.md) {
              Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AppColor.detail)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous).fill(AppColor.detail.opacity(0.12)))
              VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Valitse kuva").font(AppTypography.headline).foregroundColor(AppColor.textPrimary)
                Text("Kuvakaappaus koulun viestistä tai kutsusta").font(AppTypography.body).foregroundColor(AppColor.textSecondary)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundColor(AppColor.textSecondary)
            }
            .padding(AppSpacing.md)
            .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous).fill(AppColor.card).appShadow(AppShadow.small))
          }
          .buttonStyle(.plain)
          .disabled(isProcessing)

          if let errorText {
            Text(errorText)
              .font(AppTypography.body)
              .foregroundColor(AppColor.error)
          }

          if !events.isEmpty {
            SectionHeader(title: events.count == 1 ? "Löytyi tapahtuma" : "Löytyi \(events.count) tapahtumaa", subtitle: "Valitse lisättävä")
            ForEach(events) { event in
              Button {
                selected = event
              } label: {
                Card {
                  Text(event.title.isEmpty ? "Nimetön tapahtuma" : event.title)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColor.textPrimary)
                  if let start = event.start {
                    Text(start.formatted(event.isAllDay
                      ? .dateTime.locale(Locale(identifier: "fi_FI")).weekday().day().month()
                      : .dateTime.locale(Locale(identifier: "fi_FI")).weekday().day().month().hour().minute()))
                      .font(AppTypography.body)
                      .foregroundColor(AppColor.textSecondary)
                  }
                  if let location = event.location {
                    Label(location, systemImage: "mappin").font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
                  }
                  if let preparation = event.preparation {
                    Label(preparation, systemImage: "checklist").font(AppTypography.caption).foregroundColor(AppColor.textSecondary)
                  }
                  if !event.isComplete {
                    Pill(text: "Tarkista tiedot", systemImage: "exclamationmark.circle", color: AppColor.detail)
                  }
                }
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Sulje") { dismiss() } }
      }
      .fullScreenCover(isPresented: $isShowingCamera) {
        ImagePicker(sourceType: .camera, onImagePicked: { process($0) })
          .ignoresSafeArea()
      }
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
            process(picked)
          }
        }
      }
      .sheet(item: $selected) { event in
        let area = Self.guessArea(for: event, in: model.state)
        TaskEditorView(imported: event, areaID: area?.id, prepLeadDays: area?.kind.defaultLeadDays ?? 2)
      }
      .sheet(isPresented: $isShowingConsent) {
        AIConsentSheet(
          onAccept: {
            DeviceSettings.aiConsentAccepted = true
            isShowingConsent = false
          },
          onDecline: {
            isShowingConsent = false
            dismiss()
          }
        )
        .interactiveDismissDisabled()
      }
    }
  }

  private func process(_ picked: UIImage) {
    image = picked
    events = []
    errorText = nil
    isProcessing = true
    Task {
      do {
        events = try await service.events(in: picked)
        if events.count == 1 { selected = events.first }
      } catch {
        errorText = error.localizedDescription
      }
      isProcessing = false
    }
  }

  /// A first guess of the area: Claude's suggestion, else words in the event. The user can change it in the editor.
  static func guessArea(for event: ImportedEvent, in state: FamilyState) -> Area? {
    if let kind = event.areaKind,
       let area = state.areas.first(where: { $0.kind == kind && $0.enabled && $0.subjectMemberID == nil }) {
      return area
    }
    let text = [event.title, event.notes ?? "", event.location ?? ""].joined(separator: " ").lowercased()
    let rules: [(AreaKind, [String])] = [
      (.parties, ["synttär", "syntymäpäiv", "juhla", "kutsu", "party", "birthday"]),
      (.hobbies, ["treeni", "harjoitu", "turnaus", "ottelu", "kisa", "leiri", "seura", "kerho", "tanssi", "uinti", "jalkapallo", "salibandy", "jääkiekko"]),
      (.school, ["koulu", "päiväkoti", "luokka", "retki", "vanhempainilta", "opettaja", "valokuvaus", "eskari"]),
      (.holidays, ["joulu", "pääsiäi", "vappu", "halloween", "juhannus", "äitienpäivä", "isänpäivä"]),
      (.clothing, ["vaate", "haalari", "kengät", "kirpputori"]),
    ]
    guard let kind = rules.first(where: { _, words in words.contains { text.contains($0) } })?.0 else { return nil }
    return state.areas.first { $0.kind == kind && $0.enabled && $0.subjectMemberID == nil }
  }
}

/// Consent before any text leaves the phone.
struct AIConsentSheet: View {
  let onAccept: () -> Void
  let onDecline: () -> Void

  var body: some View {
    Screen {
      VStack(alignment: .leading, spacing: AppSpacing.lg) {
        Image(systemName: "sparkles")
          .font(.system(size: 26, weight: .semibold))
          .foregroundColor(AppColor.onSecondary)
          .frame(width: 60, height: 60)
          .background(Circle().fill(AppColor.secondary))
        Text("Ennen kuin aloitat")
          .font(.system(size: 30, weight: .bold))
          .foregroundColor(AppColor.textPrimary)
        Text("Tasan! lukee kuvan tekstin puhelimellasi. Tapahtumien löytämiseksi teksti ja muutama laiteasetus (kieli, aikavyöhyke, kellonajan muoto) lähetetään Tasan!-palveluun, jossa sen käsittelee Anthropicin Claude-tekoäly.")
          .font(.body)
          .foregroundColor(AppColor.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Text("Kuvaa ei lähetetä. Tekstiä ei käytetä mainontaan eikä seurantaan.")
          .font(.body)
          .foregroundColor(AppColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        PrimaryButton(title: "Hyväksyn", systemImage: "checkmark", action: onAccept)
        SecondaryButton(title: "Ei nyt", action: onDecline)
      }
      .padding(.top, AppSpacing.xl)
    }
  }
}
