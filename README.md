# Tasan! – share the family load

Natiivi iPhone-sovellus (SwiftUI, iOS 17+), joka tekee perheen näkymättömän metatyön näkyväksi, jaettavaksi ja ennakoitavaksi. Tämä on MVP kahdelle aikuiselle; lapset ovat tehtävien kohteita.

Ulkoasu (värit, kortit, painikkeet, typografia) ja kuvasta tapahtumaksi -tekniikka on otettu CalendropAI:sta. Kuvasta tapahtumaksi käyttää Tasanin omaa Claude-palvelua (`Worker/`).

## Mitä MVP:ssä on

| Spesifikaation kohta | Missä |
| --- | --- |
| Perheen luonti ja aikuisen kutsuminen | `Features/Onboarding`, kutsukortti Tänään-näkymässä (iCloud-jako) |
| Jäsenprofiilit: nimi, väri, syntymäpäivä, koot, koulu, harrastukset | `Features/Settings/SettingsView.swift` (`MemberEditorView`) |
| Viisi osa-aluetta | `AreaKind` (vaatteet, koulu, harrastukset, synttärit ja juhlat, juhlapyhät) |
| Suomalainen vuosikello, muokattavissa | `TasanCore/BuiltInTemplates.swift`, `YearRule.swift`, `Features/YearClock` |
| Tehtävä: otsikko, vastuuhenkilö, tapahtuman päivä, valmistelupäivä, muistutus | `FamilyTask`, `Features/Tasks/TaskEditorView.swift` |
| Osa-aluevastuu ja tehtävävastuu | `Area.ownerID`, `FamilyTask.responsibleID`, Jako-näkymän Siirrä-painikkeet |
| Vastuun siirto hyväksynnällä, väliaikainen siirto, avoimet tehtävät | `TasanCore/Responsibility.swift`, `TransferSheet`, Tänään-näkymän pyyntökortit |
| Pyydä apua, historia | `askForHelp`, `HistoryEntry`, tehtävän Historia-osio |
| Jakonäkymä | `Features/Load/LoadView.swift` |
| Perhepalaveri: viikko ja kuukausi, yhteenveto | `TasanCore/LoadAndMeeting.swift`, `Features/Meeting` |
| Apple- ja Google-kalenterin kirjoitus ja luku | `Services/AppleCalendarService.swift`, `GoogleCalendarService.swift`, `CalendarSync.swift` |
| Oma perhekalenteri sovelluksessa | `Features/Calendar/FamilyCalendarView.swift` |
| Päällekkäisyydet ja siirtoehdotus | `OverlapDetector`, Tänään- ja Palaveri-näkymät |
| Kuvasta tapahtumaksi | `Services/EventExtractionService.swift`, `Features/Import`, oma Claude-palvelu `Worker/` |
| Push-ilmoitukset: muistutus ja vastuupyyntö | `Services/NotificationService.swift` + CloudKitin hiljaiset pushit |

## Avoimiin kysymyksiin valitut oletukset

- **Taustapalvelin:** ei omaa backendiä. Perheen tiedot ovat perheen luojan iCloudissa omassa CloudKit-vyöhykkeessä, joka jaetaan toiselle aikuiselle (`CKShare`). Molemmat puhelimet synkronoivat `CKSyncEngine`llä. Paikallisesti tiedot ovat JSON-tiedostona; SwiftDatan oma CloudKit-synkka ei tue jakamista kahden Apple ID:n välillä, joten sitä ei käytetty.
- **Ylläpitäjän suora siirto:** asetus, oletuksena pois. Päällä ollessaan ylläpitäjä voi valita siirtävänsä ilman hyväksyntää; siirto näkyy historiassa.
- **Kalenteri:** sovellus kirjoittaa omaan Tasan!-kalenteriinsa (Apple ja Google erikseen), ei käyttäjän omiin kalentereihin. Muita kalentereita vain luetaan. Kukin puhelin kirjoittaa vain oman käyttäjänsä vastuut, joten siirron jälkeen merkintä siirtyy toisen kalenteriin, kun hänen puhelimensa synkronoi.
- **Talvirenkaat** ja muut koti ja auto -asiat jätettiin pois, koska osa-alue on rajattu MVP:n ulkopuolelle.

## Rakenne

```
Packages/TasanCore   Säännöt ilman Apple-kehyksiä: malli, vuosikello, vastuun siirto,
                     jako, palaveri, päällekkäisyydet. Testattavissa `swift test`.
Tasan/App            Sovelluksen käynnistys, AppModel (ainoa tila), RootView
Tasan/Services       Tallennus, CloudKit, kalenterit, ilmoitukset, OCR + Claude
Tasan/Features       Näkymät
Tasan/DesignSystem   CalendropAI:n värit, välit, kulmat, varjot
Worker               Tasanin oma Claude-palvelu (Cloudflare Worker)
project.yml          XcodeGen-määrittely; Tasan.xcodeproj on generoitu siitä
```

## Mitä on tarkistettu ja mitä ei

- **Tarkistettu:** `TasanCore` kääntyy ja sen 25 testiä menevät läpi (Swift 6.1, Linux). Testit kattavat pääsiäisen ja liikkuvat pyhät, vuosikellon tehtävät lokakuulle, kahden puhelimen samat tehtävä-id:t, siirron hyväksynnän, kieltäytymisen, väliaikaisen siirron paluun, osa-aluesiirron, avoimet tehtävät, avun pyytämisen, jakonäkymän, palaverin agendan ja synkronoinnin "uudempi voittaa" -säännön. Xcode-projekti generoitui XcodeGenillä.
- **Ei tarkistettu:** iOS-sovelluksen koodia (SwiftUI, CloudKit, EventKit, Google) ei ole käännetty, koska Xcodea ei ole Linuxilla. Ensimmäisellä Xcode-käännöksellä voi tulla pieniä käännösvirheitä. CloudKit-jakoa, kalenterikirjoitusta ja ilmoituksia ei ole ajettu laitteella. Repo sisältää GitHub Actions -työnkulun, joka kääntää sovelluksen macOS-koneella heti kun koodi on GitHubissa.

## Käyttöönotto Xcodessa

1. Kopioi `Config/Secrets.example.xcconfig` nimelle `Config/Secrets.xcconfig` ja täytä `DEVELOPMENT_TEAM`.
2. Avaa `Tasan.xcodeproj` (tai aja ensin `xcodegen generate`, jos muutit `project.yml`:ää).
3. Apple Developer -tilillä: bundle id `fi.tasan.app` (vaihda halutessasi `project.yml`:ssä), iCloud-container `iCloud.fi.tasan.app` ja Push Notifications. Xcode luo nämä automaattisella allekirjoituksella.
4. Aja laitteella (CloudKit-jako ja pushit eivät toimi kunnolla simulaattorissa). Testaa kahdella eri Apple ID:llä: luo perhe ensimmäisellä, paina Tänään-näkymässä Kutsu ja avaa linkki toisella.
5. Ennen TestFlightia: CloudKit Consolessa *Deploy Schema Changes* tuotantoon.

### Google-kalenteri (vapaaehtoinen)

1. Google Cloud Console: ota käyttöön Google Calendar API ja luo OAuth-asiakas tyypillä iOS, bundle id `fi.tasan.app`.
2. Lisää `Secrets.xcconfig`:iin `GOOGLE_CLIENT_ID` ja `GOOGLE_REVERSED_CLIENT_ID`.
3. OAuth-suostumusnäkymään scopet `calendar.app.created`, `calendar.events.readonly` ja `calendar.calendarlist.readonly`.

Ilman näitä Google-painike kertoo, ettei Googlea ole määritetty; muu sovellus toimii.

### Kuvasta tapahtumaksi

Käyttää Tasanin omaa Cloudflare Workeria (`Worker/`, oletusosoite `tasan-ai.jussi-9cc.workers.dev`). Palvelu pitää julkaista kerran omalla Cloudflare-tilillä ja Anthropic-avaimella, ohjeet: [Worker/README.md](Worker/README.md). Osoite ja sovellusavain ovat `Config/Tasan.xcconfig`issa (`TASAN_AI_HOST`, `TASAN_AI_KEY`). Kuva luetaan puhelimessa, vain teksti lähtee palveluun, ja käyttäjä hyväksyy tämän ensimmäisellä kerralla. Claude ehdottaa myös osa-aluetta ja sitä, mitä pitää valmistella; valmistelu tulee tehtävän muistiinpanoihin.

## Testit

```
swift test --package-path Packages/TasanCore
cd Worker && npm install && npm test
```
