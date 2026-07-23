import SwiftUI
import UIKit

#if canImport(IronSource)
import IronSource
#endif

struct LevelPlayBannerAdCard: View {
    let adUnitID: String
    let maximumAdHeight: CGFloat

    @ObservedObject private var advertisingConsent = AdvertisingConsentManager.shared
    @State private var didFailToLoad = false

    var body: some View {
        Group {
            if advertisingConsent.canRequestAds,
               advertisingConsent.isLevelPlayReady,
               !didFailToLoad {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Annonce")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Color(red: 196 / 255, green: 173 / 255, blue: 243 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .fixedSize(horizontal: true, vertical: false)

                    #if canImport(IronSource)
                    LevelPlayBannerRepresentable(
                        adUnitID: adUnitID,
                        didFailToLoad: $didFailToLoad
                    )
                    .frame(maxWidth: .infinity, minHeight: maximumAdHeight, maxHeight: maximumAdHeight)
                    #endif
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: maximumAdHeight + 15,
                    maxHeight: maximumAdHeight + 15,
                    alignment: .topLeading
                )
                .background(Color.xpPanel)
            }
        }
    }
}

#if canImport(IronSource)
private struct LevelPlayBannerRepresentable: UIViewRepresentable {
    let adUnitID: String
    @Binding var didFailToLoad: Bool

    func makeUIView(context: Context) -> LPMBannerAdView {
        let banner = LPMBannerAdView(adUnitId: adUnitID)
        banner.setDelegate(context.coordinator)

        guard let viewController = Self.rootViewController else {
            didFailToLoad = true
            return banner
        }

        print("🟣 ID bannière LevelPlay chargé :", adUnitID)
        banner.loadAd(with: viewController)
        return banner
    }

    func updateUIView(_ uiView: LPMBannerAdView, context: Context) {}

    static func dismantleUIView(_ uiView: LPMBannerAdView, coordinator: Coordinator) {
        uiView.destroy()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(didFailToLoad: $didFailToLoad)
    }

    private static var rootViewController: UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController

        var visible = root
        while let presented = visible?.presentedViewController {
            visible = presented
        }
        return visible
    }

    final class Coordinator: NSObject, LPMBannerAdViewDelegate {
        private let didFailToLoad: Binding<Bool>

        init(didFailToLoad: Binding<Bool>) {
            self.didFailToLoad = didFailToLoad
        }

        func didLoadAd(with adInfo: LPMAdInfo) {
            print("🟢 Bannière LevelPlay chargée")
            didFailToLoad.wrappedValue = false
        }

        func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
            print("🔴 Échec bannière LevelPlay \(adUnitId) :", error.localizedDescription)
            didFailToLoad.wrappedValue = true
        }
    }
}
#endif
