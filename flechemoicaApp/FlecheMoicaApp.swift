import FirebaseCore
import GoogleSignIn
import SwiftUI
import UserNotifications

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

#if canImport(FirebaseAppCheck)
final class FlecheMoicaAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}
#endif

@main
struct FlecheMoicaApp: App {
    @UIApplicationDelegateAdaptor(FlecheMoicaPushAppDelegate.self) private var pushAppDelegate

    init() {
        #if canImport(FirebaseAppCheck)
        AppCheck.setAppCheckProviderFactory(
            FlecheMoicaAppCheckProviderFactory()
        )
        #endif

        FirebaseConfiguration.shared.setLoggerLevel(.min)
        FirebaseApp.configure()

        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                print("Impossible de supprimer le badge :", error)
            }
        }

        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("app_started", parameters: nil)
        #endif

    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
