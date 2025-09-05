import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    Auth.auth().useAppLanguage()
    return true
  }
}

@main
struct LockInApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var auth = AuthViewModel()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ContentView()
          .environmentObject(auth)
      }
    }
  }
}
