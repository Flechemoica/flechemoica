import FirebaseCore
import GoogleSignIn
import SwiftUI

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

#if canImport(GoogleMobileAds)
import GoogleMobileAds
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

        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("app_started", parameters: nil)
        #endif

        #if canImport(GoogleMobileAds)
        if Bundle.main.object(
            forInfoDictionaryKey: "GADApplicationIdentifier"
        ) != nil {
            MobileAds.shared.start(completionHandler: nil)
        }
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
