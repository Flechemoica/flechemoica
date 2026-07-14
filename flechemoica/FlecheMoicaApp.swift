import FirebaseCore
import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct FlecheMoicaApp: App {
    init() {
        FirebaseApp.configure()

        #if canImport(GoogleMobileAds)
        if Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") != nil {
            MobileAds.shared.start(completionHandler: nil)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
