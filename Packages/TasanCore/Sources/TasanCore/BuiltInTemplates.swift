import Foundation

/*
 * The Finnish year clock that ships with the app. Families choose
 * which templates are on during onboarding and can edit any of
 * them later. Dates that vary by school or club (school photos,
 * parent evenings) are reminders to check the date, not guesses.
 */
public enum BuiltInTemplates {
  public static func all() -> [YearTemplate] {
    clothing + school + hobbies + parties + holidays
  }

  static let byKey: [String: YearTemplate] = Dictionary(
    uniqueKeysWithValues: all().compactMap { template in template.builtInKey.map { ($0, template) } }
  )

  private static func t(
    _ key: String,
    _ kind: AreaKind,
    _ title: String,
    _ rule: YearRule,
    lead: Int,
    scope: TemplateScope = .family,
    notes: String? = nil
  ) -> YearTemplate {
    YearTemplate(
      builtInKey: key,
      areaKind: kind,
      title: title,
      notes: notes,
      rule: rule,
      leadDays: lead,
      scope: rule.isPerMember ? .perChild : scope
    )
  }

  static let clothing: [YearTemplate] = [
    t("clothing.spring-mud", .clothing, "Kurahousut ja kumisaappaat", .fixed(month: 4, day: 1), lead: 14, scope: .perChild,
      notes: "Tarkista koot ja kunto, hanki puuttuvat."),
    t("clothing.summer-swap", .clothing, "Kausivaihto: kesävaatteet esiin", .fixed(month: 5, day: 15), lead: 21, scope: .perChild,
      notes: "Kesäkengät, sandaalit, uikkarit, aurinkohattu."),
    t("clothing.name-labels", .clothing, "Nimikoinnit koulun ja päiväkodin alkuun", .fixed(month: 8, day: 10), lead: 14, scope: .perChild),
    t("clothing.autumn-swap", .clothing, "Kausivaihto: syysvaatteet esiin", .fixed(month: 9, day: 1), lead: 21, scope: .perChild,
      notes: "Välikausihaalari, kurahousut, pipot."),
    t("clothing.reflectors", .clothing, "Heijastimet ja pyörän valot", .fixed(month: 10, day: 1), lead: 7),
    t("clothing.winter-size", .clothing, "Toppahaalarin ja talvikenkien koko", .fixed(month: 10, day: 20), lead: 21, scope: .perChild,
      notes: "Sovita viime talven toppahaalari ja kengät. Kirjaa uusi koko profiiliin."),
    t("clothing.winter-swap", .clothing, "Kausivaihto: talvivaatteet esiin", .fixed(month: 11, day: 1), lead: 14, scope: .perChild,
      notes: "Lapaset, kypärämyssy, villasukat, varahanskat päiväkotiin."),
  ]

  static let school: [YearTemplate] = [
    t("school.start", .school, "Koulun ja päiväkodin alku", .fixed(month: 8, day: 10), lead: 14,
      notes: "Lukujärjestys, koulutarvikkeet, reppu, iltapäiväkerho."),
    t("school.photo", .school, "Koulukuvaus: tarkista päivä", .fixed(month: 9, day: 15), lead: 7),
    t("school.parent-evening", .school, "Syksyn vanhempainillat", .fixed(month: 9, day: 1), lead: 3,
      notes: "Katso päivät koulun viesteistä ja sovi kuka menee."),
    t("school.autumn-break", .school, "Syysloman järjestelyt", .isoWeek(week: 42, weekday: 1), lead: 28,
      notes: "Hoito, lomat, matkat ja ohjelma syyslomaviikolle."),
    t("school.christmas-break", .school, "Joululoman hoitojärjestelyt", .fixed(month: 12, day: 20), lead: 28),
    t("school.winter-break", .school, "Hiihtoloman järjestelyt", .winterHoliday, lead: 28,
      notes: "Hoito, mökki, välineet. Hiihtoloman viikon voi vaihtaa asetuksista."),
    t("school.spring-party", .school, "Kevätjuhla: asu ja kukat opettajalle", .isoWeek(week: 22, weekday: 6), lead: 7),
    t("school.summer-care", .school, "Kesän hoitojärjestelyt", .isoWeek(week: 22, weekday: 6), lead: 60,
      notes: "Leirit, isovanhemmat, lomat. Sovi viikot ajoissa."),
  ]

  static let hobbies: [YearTemplate] = [
    t("hobbies.spring-fees", .hobbies, "Kevätkauden harrastusmaksut", .fixed(month: 1, day: 15), lead: 7),
    t("hobbies.summer-camps", .hobbies, "Kesäleirien ilmoittautumiset", .fixed(month: 2, day: 15), lead: 14,
      notes: "Suositut leirit täyttyvät helmikuussa."),
    t("hobbies.autumn-signup", .hobbies, "Syyskauden ilmoittautumiset", .fixed(month: 8, day: 15), lead: 14),
    t("hobbies.gear-size", .hobbies, "Harrastusvälineiden koot", .fixed(month: 8, day: 20), lead: 14, scope: .perChild,
      notes: "Luistimet, kypärä, pelikengät, suksien pituus."),
    t("hobbies.autumn-fees", .hobbies, "Syyskauden harrastusmaksut", .fixed(month: 9, day: 15), lead: 7),
  ]

  static let parties: [YearTemplate] = [
    t("parties.own-party", .parties, "Synttärijuhlat", .birthday(offset: 0), lead: 30,
      notes: "Päivä, paikka, kutsut, tarjoilut."),
    t("parties.own-present", .parties, "Synttärilahja", .birthday(offset: 0), lead: 14),
  ]

  static let holidays: [YearTemplate] = [
    t("holidays.valentine", .holidays, "Ystävänpäivä: kortit kavereille", .fixed(month: 2, day: 14), lead: 5),
    t("holidays.shrovetide", .holidays, "Laskiainen: pulkka ja laskiaispullat", .easter(offset: -47), lead: 7),
    t("holidays.palm-sunday", .holidays, "Virpominen: noita-asu ja vitsat", .easter(offset: -7), lead: 7),
    t("holidays.easter", .holidays, "Pääsiäinen: koristelut, rairuoho ja munat", .easter(offset: 0), lead: 14,
      notes: "Rairuoho kylvetään noin kaksi viikkoa ennen."),
    t("holidays.vappu", .holidays, "Vappu: ilmapallot, sima ja munkit", .fixed(month: 5, day: 1), lead: 10),
    t("holidays.mothers-day", .holidays, "Äitienpäivä", .nthWeekday(month: 5, weekday: 7, n: 2), lead: 7),
    t("holidays.midsummer", .holidays, "Juhannus", .midsummerEve, lead: 14),
    t("holidays.halloween", .holidays, "Halloween-asu", .fixed(month: 10, day: 31), lead: 14),
    t("holidays.fathers-day", .holidays, "Isänpäivä", .nthWeekday(month: 11, weekday: 7, n: 2), lead: 7),
    t("holidays.advent-calendar", .holidays, "Joulukalenterit", .fixed(month: 12, day: 1), lead: 14),
    t("holidays.decorations", .holidays, "Joulukoristelut", .nthWeekday(month: 12, weekday: 7, n: 1), lead: 5),
    t("holidays.christmas-party", .holidays, "Koulun joulujuhla: asu", .fixed(month: 12, day: 19), lead: 14),
    t("holidays.christmas-gifts", .holidays, "Joululahjat", .fixed(month: 12, day: 24), lead: 30),
  ]
}
