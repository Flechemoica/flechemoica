import SwiftUI
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct HomeBannerAdCard: View {
    let adUnitID: String
    let maximumAdHeight: CGFloat
    @State private var didFailToLoad = false

    private var effectiveAdUnitID: String {
        return adUnitID
    }

    var body: some View {
        Group {
            if !didFailToLoad {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Annonce")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(height: 15, alignment: .center)
                        .background(Color(red: 196 / 255, green: 173 / 255, blue: 243 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .fixedSize(horizontal: true, vertical: false)
                        .zIndex(1)

                    #if canImport(GoogleMobileAds)
                    GeometryReader { proxy in
                        BannerAdRepresentable(
                            adUnitID: effectiveAdUnitID,
                            availableWidth: proxy.size.width,
                            maximumHeight: maximumAdHeight,
                            didFailToLoad: $didFailToLoad
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: maximumAdHeight, maxHeight: maximumAdHeight)
                    .frame(maxWidth: .infinity)
                    #else
                    Text("Le SDK GoogleMobileAds n'est pas lié à cette cible.")
                        .font(.custom("Tahoma", size: 13))
                        .frame(maxWidth: .infinity, minHeight: maximumAdHeight, maxHeight: maximumAdHeight)
                    #endif
                }
                .frame(maxWidth: .infinity, minHeight: maximumAdHeight + 15, maxHeight: maximumAdHeight + 15, alignment: .topLeading)
                .background(Color.xpPanel)
            }
        }
    }
}

#if canImport(GoogleMobileAds)
private struct BannerAdRepresentable: UIViewRepresentable {
    let adUnitID: String
    let availableWidth: CGFloat
    let maximumHeight: CGFloat
    @Binding var didFailToLoad: Bool

    func makeUIView(context: Context) -> BannerView {
        let adaptiveSize = inlineAdaptiveBanner(
            width: availableWidth,
            maxHeight: maximumHeight
        )
        let banner = BannerView(adSize: adaptiveSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        banner.delegate = context.coordinator
        print("🟣 ID bannière adaptative AdMob réellement chargé :", adUnitID)
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(didFailToLoad: $didFailToLoad)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        private let didFailToLoad: Binding<Bool>

        init(didFailToLoad: Binding<Bool>) {
            self.didFailToLoad = didFailToLoad
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("🟢 Bannière AdMob chargée")
            didFailToLoad.wrappedValue = false
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            let nsError = error as NSError
            print("🔴 ÉCHEC BANNIÈRE ADMOB")
            print("🔴 Domaine :", nsError.domain)
            print("🔴 Code :", nsError.code)
            print("🔴 Description :", nsError.localizedDescription)
            print("🔴 Informations :", nsError.userInfo)
            didFailToLoad.wrappedValue = true
        }
    }
}
#endif
