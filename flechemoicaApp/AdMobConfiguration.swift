import Foundation

@MainActor
enum AdMobConfiguration {

    private static let productionNativeAdUnitID =
        "ca-app-pub-1003964550278910/6276883284"

    private static let productionRewardedAdUnitID =
        "ca-app-pub-1003964550278910/8860825770"

    private static let testNativeAdUnitID =
        "ca-app-pub-3940256099942544/3986624511"

    private static let testRewardedAdUnitID =
        "ca-app-pub-3940256099942544/1712485313"

    static var usesTestAds: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func nativeAdUnitID(productionID: String) -> String {
        return usesTestAds ? testNativeAdUnitID : (productionID.isEmpty ? productionNativeAdUnitID : productionID)
    }

    static func rewardedAdUnitID(productionID: String) -> String {
        return usesTestAds ? testRewardedAdUnitID : (productionID.isEmpty ? productionRewardedAdUnitID : productionID)
    }
}
