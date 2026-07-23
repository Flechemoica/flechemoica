import AppTrackingTransparency
import Combine
import Foundation
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(IronSource)
import IronSource
#endif

#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

@MainActor
final class AdvertisingConsentManager: ObservableObject {
    static let shared = AdvertisingConsentManager()

    @Published private(set) var canRequestAds = false
    @Published private(set) var isLevelPlayReady = false
    private var preparationTask: Task<Void, Never>?

    private init() {}

    func prepareAfterAuthentication() {
        guard !canRequestAds, preparationTask == nil else {
            return
        }

        preparationTask = Task { [weak self] in
            guard let self else { return }

            let umpAllowsAds = await gatherGoogleConsent()
            await requestTrackingPermissionIfNeeded()

            guard umpAllowsAds else {
                preparationTask = nil
                return
            }

            startGoogleMobileAds()
            startLevelPlay()
            canRequestAds = true
            preparationTask = nil
        }
    }

    private func gatherGoogleConsent() async -> Bool {
        #if canImport(UserMessagingPlatform)
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            print("Impossible de terminer le consentement publicitaire Google :", error)
        }

        return ConsentInformation.shared.canRequestAds
        #else
        return true
        #endif
    }

    private func requestTrackingPermissionIfNeeded() async {
        guard Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") != nil,
              ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return
        }

        try? await Task.sleep(for: .milliseconds(800))

        while !Task.isCancelled, UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(250))
        }

        guard !Task.isCancelled,
              ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return
        }

        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }

    private func startGoogleMobileAds() {
        #if canImport(GoogleMobileAds)
        #if DEBUG
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "2e253a88deb5639735e1a447219311b4"
        ]
        #endif

        MobileAds.shared.start()
        #endif
    }

    private func startLevelPlay() {
        #if canImport(IronSource)
        let request = LPMInitRequest(appKey: "274fcfac5", userId: nil)
        LevelPlay.initWith(request) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    print("🔴 Initialisation LevelPlay impossible :", error.localizedDescription)
                    self?.isLevelPlayReady = false
                    return
                }

                print("🟢 LevelPlay initialisé")
                self?.isLevelPlayReady = true
            }
        }
        #endif
    }
}
