import SwiftUI
import UIKit
import Combine
import FirebaseFirestore

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

enum AdStatsRecorder {
    static func record(userID: String?, placement: String, event: String) {
        guard let userID, !userID.isEmpty else { return }

        let placementKey = placement == "rewarded" ? "rewarded" : "native"
        let eventKey = event == "click" ? "Clicks" : "Impressions"
        let totalKey = event == "click" ? "totalClicks" : "totalImpressions"

        Firestore.firestore()
            .collection("users")
            .document(userID)
            .setData([
                "adStats": [
                    totalKey: FieldValue.increment(Int64(1)),
                    "\(placementKey)\(eventKey)": FieldValue.increment(Int64(1))
                ],
                "adStatsUpdatedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }
}

struct HomeNativeAdCard: View {
    let adUnitID: String
    let userID: String
    var mediaAspectRatio: CGFloat = 16 / 9
    var fillsAvailableSpace = false

    var body: some View {
        #if canImport(GoogleMobileAds)
        if Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") != nil {
            NativeAdContainer(
                adUnitID: adUnitID,
                userID: userID,
                mediaAspectRatio: mediaAspectRatio,
                fillsAvailableSpace: fillsAvailableSpace
            )
        } else {
            NativeAdPlaceholder(
                message: "ID application AdMob manquant dans Info.plist.",
                fillsAvailableSpace: fillsAvailableSpace
            )
        }
        #else
        NativeAdPlaceholder(
            message: "Le SDK GoogleMobileAds n'est pas lié à cette cible.",
            fillsAvailableSpace: fillsAvailableSpace
        )
        #endif
    }
}

private struct NativeAdPlaceholder: View {
    let message: String
    let fillsAvailableSpace: Bool

    init(
        message: String = "Chargement de l'annonce native AdMob...",
        fillsAvailableSpace: Bool = false
    ) {
        self.message = message
        self.fillsAvailableSpace = fillsAvailableSpace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AdBadgeIcon()
                Text("Annonce")
                    .font(.xpTahoma(size: 18, weight: .bold))
                    .foregroundStyle(.black)
            }
            Text(message)
                .font(.custom("Tahoma", size: 13))
                .foregroundStyle(.black)
                .lineLimit(2)
        }
        .frame(height: fillsAvailableSpace ? nil : 78)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }
}

private struct AdBadgeIcon: View {
    var body: some View {
        Text("Annonce")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 58, height: 20)
            .background(Color(red: 192 / 255, green: 173 / 255, blue: 238 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

#if canImport(GoogleMobileAds)
private struct NativeAdContainer: View {
    let adUnitID: String
    let userID: String
    let mediaAspectRatio: CGFloat
    let fillsAvailableSpace: Bool
    @StateObject private var loader = NativeAdLoader()

    private var effectiveAdUnitID: String {
        AdMobConfiguration.nativeAdUnitID(productionID: adUnitID)
    }

    var body: some View {
        Group {
            if let nativeAd = loader.nativeAd {
                NativeAdRepresentable(
                    nativeAd: nativeAd,
                    mediaAspectRatio: mediaAspectRatio
                )
                    .id(mediaAspectRatio)
                    .frame(height: fillsAvailableSpace ? nil : 280)
                    .frame(maxWidth: .infinity, maxHeight: fillsAvailableSpace ? .infinity : nil)
                    .background(Color.xpPanel)
                    .overlay {
                        if !fillsAvailableSpace {
                            Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2)
                        }
                    }
            } else {
                NativeAdPlaceholder(
                    message: loader.placeholderMessage,
                    fillsAvailableSpace: fillsAvailableSpace
                )
            }
        }
        .onAppear {
            Task {
                await AdMobConfiguration.refreshTestAdsStatus()
                loader.load(adUnitID: effectiveAdUnitID, userID: userID)
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
    private var statsUserID: String?

    func load(adUnitID: String, userID: String) {
        guard nativeAd == nil, !isLoading else {
            return
        }

        statsUserID = userID
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

        let nativeAdViewOptions = NativeAdViewAdOptions()
        nativeAdViewOptions.preferredAdChoicesPosition = .bottomRightCorner

        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: [nativeAdViewOptions]
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
            nativeAd.delegate = self
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

extension NativeAdLoader: NativeAdDelegate {
    nonisolated func nativeAdDidRecordImpression(_ nativeAd: NativeAd) {
        Task { @MainActor in
            AdStatsRecorder.record(userID: statsUserID, placement: "native", event: "impression")
        }
    }

    nonisolated func nativeAdDidRecordClick(_ nativeAd: NativeAd) {
        Task { @MainActor in
            AdStatsRecorder.record(userID: statsUserID, placement: "native", event: "click")
        }
    }
}

private struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd
    let mediaAspectRatio: CGFloat

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = UIColor(Color.xpPanel)

        let adBadge = UILabel()
        adBadge.text = "Annonce"
        adBadge.font = .boldSystemFont(ofSize: 9)
        adBadge.textColor = .black
        adBadge.textAlignment = .center
        adBadge.backgroundColor = UIColor(
            red: 192 / 255,
            green: 173 / 255,
            blue: 238 / 255,
            alpha: 1
        )
        adBadge.layer.cornerRadius = 2
        adBadge.clipsToBounds = true
        adBadge.translatesAutoresizingMaskIntoConstraints = false

        let mediaView = MediaView()
        mediaView.backgroundColor = UIColor.black.withAlphaComponent(0.04)
        mediaView.contentMode = .scaleAspectFit
        mediaView.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        mediaView.layer.borderWidth = 1
        mediaView.clipsToBounds = true
        mediaView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        iconView.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        iconView.layer.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
        iconView.layer.borderWidth = 1
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let headlineLabel = UILabel()
        headlineLabel.font = UIFont(name: "Tahoma-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
        headlineLabel.textColor = .black
        headlineLabel.numberOfLines = 2
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        let bodyLabel = UILabel()
        bodyLabel.font = UIFont(name: "Tahoma", size: 13) ?? .systemFont(ofSize: 13)
        bodyLabel.textColor = UIColor.black.withAlphaComponent(0.72)
        bodyLabel.numberOfLines = 2
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let starRatingLabel = UILabel()
        starRatingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        starRatingLabel.textColor = UIColor(red: 0.86, green: 0.56, blue: 0.02, alpha: 1)
        starRatingLabel.numberOfLines = 1
        starRatingLabel.translatesAutoresizingMaskIntoConstraints = false

        let callToActionButton = UIButton(type: .system)
        callToActionButton.titleLabel?.font = UIFont(name: "Tahoma-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
        callToActionButton.setTitleColor(.black, for: .normal)
        callToActionButton.backgroundColor = UIColor(Color.xpChrome)
        callToActionButton.layer.borderColor = UIColor(Color.xpBlueMid).cgColor
        callToActionButton.layer.borderWidth = 1
        callToActionButton.isUserInteractionEnabled = false
        callToActionButton.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(mediaView)
        adView.addSubview(adBadge)
        adView.addSubview(iconView)
        adView.addSubview(headlineLabel)
        adView.addSubview(bodyLabel)
        adView.addSubview(starRatingLabel)
        adView.addSubview(callToActionButton)

        adView.mediaView = mediaView
        adView.iconView = iconView
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.starRatingView = starRatingLabel
        adView.callToActionView = callToActionButton

        NSLayoutConstraint.activate([
            adBadge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
            adBadge.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            adBadge.widthAnchor.constraint(equalToConstant: 58),
            adBadge.heightAnchor.constraint(equalToConstant: 20),

            mediaView.topAnchor.constraint(equalTo: adView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            mediaView.heightAnchor.constraint(
                equalTo: mediaView.widthAnchor,
                multiplier: 1 / mediaAspectRatio
            ),

            iconView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 10),
            iconView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            iconView.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -24),

            headlineLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            headlineLabel.trailingAnchor.constraint(equalTo: callToActionButton.leadingAnchor, constant: -10),

            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),

            starRatingLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 2),
            starRatingLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            starRatingLabel.trailingAnchor.constraint(lessThanOrEqualTo: headlineLabel.trailingAnchor),
            starRatingLabel.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -24),

            callToActionButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            callToActionButton.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 17),
            callToActionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            callToActionButton.heightAnchor.constraint(equalToConstant: 30),
            callToActionButton.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -24)
        ])

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        let iconView = adView.iconView as? UIImageView
        iconView?.image = nativeAd.icon?.image
        iconView?.isHidden = nativeAd.icon == nil

        (adView.headlineView as? UILabel)?.text = nativeAd.headline

        let bodyLabel = adView.bodyView as? UILabel
        bodyLabel?.text = nativeAd.body
        bodyLabel?.isHidden = nativeAd.body == nil

        let starRatingLabel = adView.starRatingView as? UILabel
        if let rating = nativeAd.starRating?.doubleValue {
            starRatingLabel?.text = starRatingText(for: rating)
            starRatingLabel?.accessibilityLabel = String(format: "Note %.1f sur 5", rating)
            starRatingLabel?.isHidden = false
        } else {
            starRatingLabel?.text = nil
            starRatingLabel?.isHidden = true
        }

        let callToActionButton = adView.callToActionView as? UIButton
        callToActionButton?.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
        callToActionButton?.isHidden = nativeAd.callToAction == nil

        adView.mediaView?.isHidden = nativeAd.mediaContent.hasVideoContent == false
            && nativeAd.mediaContent.mainImage == nil
        adView.nativeAd = nativeAd
    }

    private func starRatingText(for rating: Double) -> String {
        let filledStars = max(0, min(5, Int(rating.rounded())))
        return String(repeating: "★", count: filledStars)
            + String(repeating: "☆", count: 5 - filledStars)
            + String(format: "  %.1f", rating)
    }
}
#endif
