import CloudKit
import SwiftUI
import UIKit

@main
struct TasanApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(appDelegate.model)
        .tint(AppColor.primary)
        .onOpenURL { appDelegate.model.handle(url: $0) }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { appDelegate.model.becameActive() }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
  /// SwiftUI wraps the app delegate, so `UIApplication.shared.delegate` is not this object.
  static private(set) var shared: AppDelegate?
  let model = AppModel()

  override init() {
    super.init()
    AppDelegate.shared = self
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    model.launch()
    // CKSyncEngine relies on silent pushes from CloudKit for the shared family zone.
    application.registerForRemoteNotifications()
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any]
  ) async -> UIBackgroundFetchResult {
    // A change in the family zone: fetch it so requests and reminders are current.
    await model.sync.syncNow()
    return .newData
  }
}

/// Receives the iCloud share link when the invited adult taps it.
@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
  func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    guard let delegate = AppDelegate.shared else { return }
    Task {
      await delegate.model.acceptShare(metadata)
    }
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    // A cold start from the share link delivers the metadata here instead.
    if let metadata = connectionOptions.cloudKitShareMetadata,
      let delegate = AppDelegate.shared
    {
      Task {
        await delegate.model.acceptShare(metadata)
      }
    }
  }
}
