import Foundation

@MainActor
enum AdMobConfiguration {
    private static let nativeTestAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    private static let rewardedTestAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    static var usesTestAds: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func refreshTestAdsStatus() async {
        // Rien à faire
    }

    static func nativeAdUnitID(productionID: String) -> String {
        usesTestAds ? nativeTestAdUnitID : productionID
    }

    static func rewardedAdUnitID(productionID: String) -> String {
        usesTestAds ? rewardedTestAdUnitID : productionID
    }
}
