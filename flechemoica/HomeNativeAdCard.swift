import SwiftUI
import UIKit
import Combine

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct HomeNativeAdCard: View {
    let adUnitID: String

    var body: some View {
        #if canImport(GoogleMobileAds)
        if Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") != nil {
            NativeAdContainer(adUnitID: adUnitID)
        } else {
            NativeAdPlaceholder(message: "ID application AdMob manquant dans Info.plist.")
        }
        #else
        NativeAdPlaceholder(message: "Le SDK GoogleMobileAds n'est pas lié à cette cible.")
        #endif
    }
}

private struct NativeAdPlaceholder: View {
    let message: String

    init(message: String = "Chargement de l'annonce native AdMob...") {
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AdBadgeIcon()
                Text("Publicité")
                    .font(.xpTahoma(size: 18, weight: .bold))
                    .foregroundStyle(.black)
            }
            Text(message)
                .font(.custom("Tahoma", size: 13))
                .foregroundStyle(.black)
                .lineLimit(2)
        }
        .frame(height: 78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }
}

private struct AdBadgeIcon: View {
    var body: some View {
        Text("Ad")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 20)
            .background(Color(red: 0.99, green: 0.71, blue: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

#if canImport(GoogleMobileAds)
private struct NativeAdContainer: View {
    let adUnitID: String
    @StateObject private var loader = NativeAdLoader()

    private var effectiveAdUnitID: String {
        AdMobConfiguration.nativeAdUnitID(productionID: adUnitID)
    }

    var body: some View {
        Group {
            if let nativeAd = loader.nativeAd {
                NativeAdRepresentable(nativeAd: nativeAd)
                    .frame(height: 106)
                    .background(Color.xpPanel)
                    .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
            } else {
                NativeAdPlaceholder(message: loader.placeholderMessage)
            }
        }
        .onAppear {
            Task {
                await AdMobConfiguration.refreshTestAdsStatus()
                loader.load(adUnitID: effectiveAdUnitID)
            }
        }
    }
}

@MainActor
private final class NativeAdLoader: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published var nativeAd: NativeAd?
    @Published private(set) var placeholderMessage = "Chargement de l'annonce native AdMob..."

    private var adLoader: AdLoader?
    private var isLoading = false
    private var retryCount = 0

    func load(adUnitID: String) {
        guard nativeAd == nil, !isLoading else {
            return
        }

        isLoading = true
        placeholderMessage = "Chargement de l'annonce native AdMob..."

        MobileAds.shared.start { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.loadAd(adUnitID: adUnitID)
            }
        }
    }

    private func loadAd(adUnitID: String) {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            retryLoad(adUnitID: adUnitID)
            return
        }

        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    private func retryLoad(adUnitID: String) {
        guard retryCount < 5 else {
            isLoading = false
            placeholderMessage = "Impossible de trouver la fenêtre active pour charger l'annonce."
            return
        }

        retryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.loadAd(adUnitID: adUnitID)
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in
            self.nativeAd = nativeAd
            self.isLoading = false
            self.retryCount = 0
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in
            self.nativeAd = nil
            self.isLoading = false
            self.retryCount = 0
            self.placeholderMessage = "Annonce indisponible: \(error.localizedDescription)"
        }
    }
}

private struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = UIColor(Color.xpPanel)

        let headlineLabel = UILabel()
        headlineLabel.font = UIFont(name: "Tahoma-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
        headlineLabel.textColor = .black
        headlineLabel.numberOfLines = 1
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        let bodyLabel = UILabel()
        bodyLabel.font = UIFont(name: "Tahoma", size: 13) ?? .systemFont(ofSize: 13)
        bodyLabel.textColor = .black
        bodyLabel.numberOfLines = 1
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let callToActionButton = UIButton(type: .system)
        callToActionButton.titleLabel?.font = UIFont(name: "Tahoma-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
        callToActionButton.setTitleColor(.black, for: .normal)
        callToActionButton.backgroundColor = UIColor(Color.xpChrome)
        callToActionButton.layer.borderColor = UIColor(Color.xpBlueMid).cgColor
        callToActionButton.layer.borderWidth = 1
        callToActionButton.isUserInteractionEnabled = false
        callToActionButton.translatesAutoresizingMaskIntoConstraints = false

        let adBadge = UILabel()
        adBadge.text = "Ad"
        adBadge.font = .boldSystemFont(ofSize: 11)
        adBadge.textColor = .white
        adBadge.textAlignment = .center
        adBadge.backgroundColor = UIColor(red: 0.99, green: 0.71, blue: 0.11, alpha: 1)
        adBadge.layer.cornerRadius = 2
        adBadge.clipsToBounds = true
        adBadge.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(adBadge)
        adView.addSubview(headlineLabel)
        adView.addSubview(bodyLabel)
        adView.addSubview(callToActionButton)

        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = callToActionButton

        NSLayoutConstraint.activate([
            adBadge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
            adBadge.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            adBadge.widthAnchor.constraint(equalToConstant: 28),
            adBadge.heightAnchor.constraint(equalToConstant: 20),

            callToActionButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            callToActionButton.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            callToActionButton.widthAnchor.constraint(equalToConstant: 96),
            callToActionButton.heightAnchor.constraint(equalToConstant: 30),

            headlineLabel.topAnchor.constraint(equalTo: adBadge.bottomAnchor, constant: 4),
            headlineLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            headlineLabel.trailingAnchor.constraint(equalTo: callToActionButton.leadingAnchor, constant: -10),

            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),
            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -10)
        ])

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body
        (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        adView.nativeAd = nativeAd
    }
}
#endif
