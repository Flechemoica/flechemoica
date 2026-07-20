import AppTrackingTransparency
import Foundation
import UIKit

enum TrackingPermissionRequester {
    static func requestAfterAuthenticationIfPossible() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") != nil else {
            return
        }

        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard UIApplication.shared.applicationState == .active else {
                return
            }

            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
