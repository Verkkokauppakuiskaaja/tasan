import SwiftUI
import TasanCore

struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model

    Group {
      if model.isJoiningFamily {
        JoinFamilyView()
      } else if model.hasFamily {
        MainTabView()
      } else {
        OnboardingView()
      }
    }
    .alert(
      "Hups",
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      actions: { Button("OK", role: .cancel) {} },
      message: { Text(model.errorMessage ?? "") }
    )
  }
}

struct MainTabView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model

    TabView(selection: $model.selectedTab) {
      TodayView()
        .tabItem { Label("Tänään", systemImage: "checklist") }
        .badge(model.requestsToMe.count)
        .tag(AppTab.today)

      FamilyCalendarView()
        .tabItem { Label("Kalenteri", systemImage: "calendar") }
        .tag(AppTab.calendar)

      YearClockView()
        .tabItem { Label("Vuosikello", systemImage: "clock.arrow.circlepath") }
        .tag(AppTab.yearClock)

      LoadView()
        .tabItem { Label("Jako", systemImage: "person.2.fill") }
        .tag(AppTab.load)

      MeetingView()
        .tabItem { Label("Palaveri", systemImage: "bubble.left.and.bubble.right.fill") }
        .tag(AppTab.meeting)
    }
  }
}
