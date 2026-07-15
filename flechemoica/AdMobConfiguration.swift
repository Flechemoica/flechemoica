import Foundation
import StoreKit

@MainActor
enum AdMobConfiguration {
    private static let nativeTestAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    private static let rewardedTestAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    private static var appStoreEnvironmentUsesTestAds = false

    static var usesTestAds: Bool {
        #if DEBUGdans mon do
        return true
        #else
        return appStoreEnvironmentUsesTestAds
        #endif
    }

    static func refreshTestAdsStatus() async {
        #if DEBUG
        appStoreEnvironmentUsesTestAds = true
        #else
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction), .unverified(let transaction, _):
                appStoreEnvironmentUsesTestAds = transaction.environment == .sandbox || transaction.environment == .xcode
            }
        } catch {
            appStoreEnvironmentUsesTestAds = false
        }
        #endif
    }

    static func nativeAdUnitID(productionID: String) -> String {
        usesTestAds ? nativeTestAdUnitID : productionID
    }

    static func rewardedAdUnitID(productionID: String) -> String {
        usesTestAds ? rewardedTestAdUnitID : productionID
    }
}
