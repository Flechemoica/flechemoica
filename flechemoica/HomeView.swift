import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import UIKit
import WebKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct HomeView: View {
    let user: User
    var onUserChanged: (User) -> Void = { _ in }
    var onSignedOut: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var rewardedGridAccessAd = RewardedGridAccessAd()
    @State private var isEditor = false
    @State private var isShowingPublicProfile = false
    @State private var isShowingSettings = false
    @State private var publishedGrids: [PublishedGrid] = []
    @State private var selectedGridIndex = 0
    @State private var selectedGameGrid: PublishedGrid?
    @State private var publicProfiles: [PublicProfile] = []
    @State private var selectedPublicProfile: PublicProfile?
    @State private var isLoadingPublicProfiles = false
    @State private var profileListMessage: String?
    @State private var rewardUnlockedGridIDs: Set<String> = []
    @State private var completedGridTitles: [String] = []
    @State private var gridAccessMessage: String?
    @State private var isLoadingPublishedGrids = false
    @State private var gridLoadingMessage: String?
    @State private var wizzShakeTrigger = 0
    @State private var displayNameOverride: String?
    @State private var emailOverride: String?
    @State private var photoURLOverride: URL?
    @State private var isDeletingAccount = false

    private var displayName: String {
        if let displayNameOverride, !displayNameOverride.isEmpty {
            return displayNameOverride
        }

        if let name = user.displayName, !name.isEmpty {
            return name
        }

        return emailAddress ?? "Utilisateur"
    }

    private var emailAddress: String? {
        if let emailOverride, !emailOverride.isEmpty {
            return emailOverride
        }

        return user.email
    }

    private var windowTitle: String {
        if isShowingSettings {
            return "Reglages.exe"
        }

        if let selectedGameGrid {
            return "\(selectedGameGrid.title).exe"
        }

        return isShowingPublicProfile ? "\(publicProfileDisplayName).exe" : "Accueil.exe"
    }

    private var avatarName: String {
        let photoURL = photoURLOverride ?? user.photoURL

        if let host = photoURL?.host, !host.isEmpty {
            return host.replacingOccurrences(of: ".png", with: "")
        }

        return "08"
    }

    private var publicProfileDisplayName: String {
        selectedPublicProfile?.displayName ?? displayName
    }

    private var publicProfileAvatarName: String {
        selectedPublicProfile?.avatarName ?? avatarName
    }

    private var publicProfileIsEditor: Bool {
        selectedPublicProfile?.isEditor ?? isEditor
    }

    private var publicProfileCompletedGridTitles: [String] {
        selectedPublicProfile?.completedGridTitles ?? completedGridTitles
    }

    private var canOpenPublicProfileSettings: Bool {
        selectedPublicProfile == nil || selectedPublicProfile?.uid == user.uid
    }

    private static func isEditorProfile(_ data: [String: Any]?) -> Bool {
        let role = (data?["role"] as? String)?.lowercased()
        let status = (data?["status"] as? String)?.lowercased()
        return role == "editor" || status == "editor"
    }

    fileprivate static func completedGridTitles(from data: [String: Any]?) -> [String] {
        if let titles = data?["completedGridTitles"] as? [String] {
            return titles.sorted()
        }

        guard let completedGrids = data?["completedGrids"] as? [String: Any] else {
            return []
        }

        return completedGrids.values
            .compactMap { ($0 as? [String: Any])?["title"] as? String }
            .sorted()
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                XPWindow(title: windowTitle) {
                    if isShowingSettings {
                        ProfileSettingsContent(
                            user: user,
                            initialDisplayName: displayName,
                            initialEmail: emailAddress ?? "",
                            initialAvatarName: avatarName,
                            backAction: { isShowingSettings = false },
                            userChanged: handleUserChanged,
                            deletingAccountChanged: { isDeletingAccount = $0 },
                            signedOut: handleSignedOut
                        )
                    } else if isShowingPublicProfile {
                        PublicProfileContent(
                            displayName: publicProfileDisplayName,
                            avatarName: publicProfileAvatarName,
                            isEditor: publicProfileIsEditor,
                            completedGridTitles: publicProfileCompletedGridTitles,
                            backAction: closePublicProfile,
                            settingsAction: canOpenPublicProfileSettings ? { isShowingSettings = true } : nil,
                            contactAction: openSupportMail
                        )
                    } else if let selectedGameGrid {
                        GridGameContent(
                            grid: selectedGameGrid,
                            userID: user.uid,
                            backAction: { self.selectedGameGrid = nil },
                            completionRecorded: recordCompletedGrid
                        )
                    } else {
                        HomeContent(
                            displayName: displayName,
                            avatarName: avatarName,
                            isEditor: isEditor,
                            selectedGrid: selectedPublishedGrid,
                            selectedGridIndex: selectedGridIndex,
                            gridCount: publishedGrids.count,
                            isLoadingPublishedGrids: isLoadingPublishedGrids,
                            gridLoadingMessage: gridLoadingMessage,
                            gridAccessMessage: gridAccessMessage ?? rewardedGridAccessAd.message,
                            isLoadingRewardedAd: rewardedGridAccessAd.isLoading,
                            requiresRewardedAd: selectedGridRequiresRewardedAd,
                            selectedGridIsCompleted: selectedGridIsCompleted,
                            profileAction: openOwnProfile,
                            previousGridAction: showPreviousGrid,
                            nextGridAction: showNextGrid,
                            playGridAction: playSelectedGrid,
                            wizzAction: triggerWizzShake
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .modifier(WizzShakeEffect(trigger: wizzShakeTrigger))
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            }
        }
        .task(id: user.uid) {
            guard !isDeletingAccount else { return }
            await refreshAuthenticatedProfile()
            await loadPublishedGrids()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !isDeletingAccount else { return }
            await refreshAuthenticatedProfile()
            await loadPublishedGrids()
        }
    }

    private func refreshAuthenticatedProfile() async {
        guard !isDeletingAccount else { return }
        try? await user.reload()
        guard !isDeletingAccount else { return }

        let refreshedUser = Auth.auth().currentUser ?? user
        displayNameOverride = refreshedUser.displayName
        emailOverride = refreshedUser.email
        photoURLOverride = refreshedUser.photoURL
        onUserChanged(refreshedUser)
        await loadProfileMetadataAndSyncEmail(for: refreshedUser)
    }

    private func loadProfileMetadataAndSyncEmail(for refreshedUser: User) async {
        guard !isDeletingAccount else { return }
        do {
            let database = Firestore.firestore()
            let document = database
                .collection("users")
                .document(refreshedUser.uid)
            let snapshot = try await document.getDocument()
            guard snapshot.exists else {
                try? Auth.auth().signOut()
                handleSignedOut()
                return
            }

            let userData = snapshot.data()
            isEditor = Self.isEditorProfile(userData)
            completedGridTitles = Self.completedGridTitles(from: userData)

            if let storedPseudo = userData?["pseudo"] as? String, !storedPseudo.isEmpty {
                displayNameOverride = storedPseudo
            }

            if let storedEmail = userData?["email"] as? String, !storedEmail.isEmpty {
                emailOverride = storedEmail
            }

            if let avatarID = userData?["avatarID"] as? String, !avatarID.isEmpty {
                photoURLOverride = URL(string: "flechemoica-avatar://\(avatarID)")
            }

            if let unlockedGridIDs = userData?["unlockedGridIDs"] as? [String] {
                rewardUnlockedGridIDs = Set(unlockedGridIDs)
            }

            await syncAuthenticatedEmailIfNeeded(
                refreshedUser: refreshedUser,
                document: document,
                storedEmail: userData?["email"] as? String
            )
        } catch {
            return
        }
    }

    private func syncAuthenticatedEmailIfNeeded(
        refreshedUser: User,
        document: DocumentReference,
        storedEmail: String?
    ) async {
        guard !isDeletingAccount else { return }
        guard let authEmail = refreshedUser.email, !authEmail.isEmpty, storedEmail != authEmail else {
            return
        }

        do {
            try await document.setData([
                "email": authEmail,
                "emailKey": authEmail.lowercased(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            emailOverride = authEmail
        } catch {
            return
        }
    }

    private var selectedPublishedGrid: PublishedGrid? {
        guard publishedGrids.indices.contains(selectedGridIndex) else {
            return nil
        }

        return publishedGrids[selectedGridIndex]
    }

    private var selectedGridRequiresRewardedAd: Bool {
        guard let selectedPublishedGrid else { return false }
        return selectedGridIndex > 0
            && !isGridCompleted(selectedPublishedGrid)
            && !rewardUnlockedGridIDs.contains(selectedPublishedGrid.id)
    }

    private var selectedGridIsCompleted: Bool {
        guard let selectedPublishedGrid else { return false }
        return isGridCompleted(selectedPublishedGrid)
    }

    private func isGridCompleted(_ grid: PublishedGrid) -> Bool {
        UserDefaults.standard.bool(forKey: userScopedGridStorageKey(prefix: "gridCompleted", gridID: grid.id))
            || completedGridTitles.contains(grid.title)
    }

    private func userScopedGridStorageKey(prefix: String, gridID: String) -> String {
        let safeUserID = user.uid
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let safeGridID = gridID
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        return "\(prefix).\(safeUserID).\(safeGridID)"
    }

    private func loadPublishedGrids() async {
        isLoadingPublishedGrids = true
        gridLoadingMessage = nil

        do {
            let snapshot = try await Firestore.firestore()
                .collection("grids")
                .whereField("status", isEqualTo: "published")
                .limit(to: 50)
                .getDocuments()

            publishedGrids = snapshot.documents
                .compactMap(PublishedGrid.init(document:))
                .sorted { $0.releaseAt > $1.releaseAt }
            selectedGridIndex = publishedGrids.isEmpty ? 0 : min(selectedGridIndex, publishedGrids.count - 1)
            gridLoadingMessage = publishedGrids.isEmpty ? "Aucune grille publiee" : nil
            await loadCompletedPlayerCounts()
        } catch {
            let nsError = error as NSError
            gridLoadingMessage = "Erreur de chargement: \(nsError.localizedDescription)"
        }

        isLoadingPublishedGrids = false
    }

    private func loadCompletedPlayerCounts() async {
        let grids = publishedGrids
        guard !grids.isEmpty else { return }

        let database = Firestore.firestore()

        for grid in grids {
            do {
                let snapshot = try await database
                    .collection("users")
                    .whereField("completedGridTitles", arrayContains: grid.title)
                    .getDocuments()
                let historicalCompletedCount = snapshot.documents.count

                if let index = publishedGrids.firstIndex(where: { $0.id == grid.id }) {
                    publishedGrids[index].completedPlayerCount = historicalCompletedCount
                }
            } catch {
                continue
            }
        }
    }

    private func showPreviousGrid() {
        guard selectedGridIndex + 1 < publishedGrids.count else { return }
        selectedGridIndex += 1
    }

    private func showNextGrid() {
        guard selectedGridIndex > 0 else { return }
        selectedGridIndex -= 1
    }

    private func playSelectedGrid() {
        guard let selectedPublishedGrid else { return }
        gridAccessMessage = nil

        guard selectedGridIndex > 0, !rewardUnlockedGridIDs.contains(selectedPublishedGrid.id) else {
            openGrid(selectedPublishedGrid)
            return
        }

        Task {
            await rewardedGridAccessAd.showAd(
                adUnitID: "ca-app-pub-1003964550278910/8860825770",
                customData: "grid_\(selectedPublishedGrid.id)"
            ) { earnedReward in
                guard earnedReward else {
                    gridAccessMessage = "Regarde la pub jusqu'au bout pour debloquer cette grille."
                    return
                }

                rewardUnlockedGridIDs.insert(selectedPublishedGrid.id)
                persistUnlockedGrid(id: selectedPublishedGrid.id)
                openGrid(selectedPublishedGrid)
            }
        }
    }

    private func openGrid(_ grid: PublishedGrid) {
        if completedGridTitles.contains(grid.title) {
            UserDefaults.standard.set(true, forKey: userScopedGridStorageKey(prefix: "gridCompleted", gridID: grid.id))
        }

        selectedGameGrid = publishedGrids.first { $0.id == grid.id } ?? grid
    }

    private func persistUnlockedGrid(id: String) {
        Task {
            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(user.uid)
                    .setData([
                        "unlockedGridIDs": FieldValue.arrayUnion([id]),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true)
            } catch {
                gridAccessMessage = "Grille debloquee sur cet appareil, mais synchronisation impossible."
            }
        }
    }

    private func loadPublicProfiles() async {
        isLoadingPublicProfiles = true
        profileListMessage = nil

        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .order(by: "pseudoKey")
                .limit(to: 50)
                .getDocuments()

            publicProfiles = snapshot.documents.compactMap(PublicProfile.init(document:))
            profileListMessage = publicProfiles.isEmpty ? "Aucun profil public" : nil
        } catch {
            let nsError = error as NSError
            profileListMessage = "Erreur de chargement: \(nsError.localizedDescription)"
        }

        isLoadingPublicProfiles = false
    }

    private func openOwnProfile() {
        selectedPublicProfile = nil
        isShowingPublicProfile = true
    }

    private func openPublicProfile(_ profile: PublicProfile) {
        selectedPublicProfile = profile
        isShowingPublicProfile = true
    }

    private func closePublicProfile() {
        selectedPublicProfile = nil
        isShowingPublicProfile = false
    }

    private func recordCompletedGrid(id: String, title: String) {
        let wasAlreadyCompleted = completedGridTitles.contains(title)
        guard !completedGridTitles.contains(title) else { return }
        completedGridTitles.append(title)
        completedGridTitles.sort()

        if !wasAlreadyCompleted, let index = publishedGrids.firstIndex(where: { $0.id == id }) {
            publishedGrids[index].completedPlayerCount += 1
        }
    }

    private func triggerWizzShake() {
        withAnimation(.linear(duration: 0.58)) {
            wizzShakeTrigger += 1
        }
    }

    private func handleUserChanged(_ changedUser: User) {
        displayNameOverride = changedUser.displayName
        emailOverride = changedUser.email
        photoURLOverride = changedUser.photoURL
        onUserChanged(changedUser)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let visibleVersion = (version?.isEmpty == false) ? version! : "1.0"

        if let build, !build.isEmpty, build != visibleVersion {
            return "Version \(visibleVersion) (\(build))"
        }

        return "Version \(visibleVersion)"
    }

    private func openSupportMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "contact@flechemoica.fr"
        components.queryItems = [
            URLQueryItem(name: "body", value: supportMailBody)
        ]

        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    private var supportMailBody: String {
        """


        Infos utilisateur
        UID : \(user.uid)
        Pseudo : \(displayName)
        E-mail : \(emailAddress ?? "Non disponible")

        Infos app
        \(appVersionText)
        iOS : \(UIDevice.current.systemVersion)
        Appareil : \(UIDevice.current.model)
        """
    }

    private func handleSignedOut() {
        onSignedOut()
    }
}

@MainActor
private final class RewardedGridAccessAd: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    #if canImport(GoogleMobileAds)
    private var rewardedAd: RewardedAd?
    private var pendingRewardCompletion: ((Bool) -> Void)?
    private var didEarnReward = false

    private var effectiveAdUnitID: String {
        AdMobConfiguration.rewardedAdUnitID(productionID: productionAdUnitID ?? "")
    }

    private var productionAdUnitID: String?
    #endif

    func showAd(
        adUnitID: String,
        customData: String,
        rewarded: @escaping (Bool) -> Void
    ) async {
        #if canImport(GoogleMobileAds)
        productionAdUnitID = adUnitID
        message = nil

        do {
            let ad = try await loadAdIfNeeded(customData: customData)
            guard let rootViewController = UIApplication.shared.activeRootViewController else {
                message = "Impossible d'ouvrir la pub pour le moment."
                rewarded(false)
                return
            }

            didEarnReward = false
            pendingRewardCompletion = rewarded
            ad.present(from: rootViewController) { [weak self] in
                Task { @MainActor in
                    self?.didEarnReward = true
                }
            }
        } catch {
            message = "Pub indisponible: \(error.localizedDescription)"
            rewarded(false)
        }
        #else
        message = "Le SDK GoogleMobileAds n'est pas lie a cette cible."
        rewarded(false)
        #endif
    }

    #if canImport(GoogleMobileAds)
    private func loadAdIfNeeded(customData: String) async throws -> RewardedAd {
        if let rewardedAd {
            return rewardedAd
        }

        return try await loadAd(customData: customData)
    }

    @discardableResult
    private func loadAd(customData: String) async throws -> RewardedAd {
        isLoading = true
        defer { isLoading = false }

        await AdMobConfiguration.refreshTestAdsStatus()
        let ad = try await RewardedAd.load(with: effectiveAdUnitID, request: Request())
        let options = ServerSideVerificationOptions()
        options.customRewardText = customData
        ad.serverSideVerificationOptions = options
        ad.fullScreenContentDelegate = self
        rewardedAd = ad
        return ad
    }

    private func finishRewardFlow(earnedReward: Bool) {
        rewardedAd = nil
        let completion = pendingRewardCompletion
        pendingRewardCompletion = nil
        completion?(earnedReward)
        Task { try? await loadAd(customData: "preload") }
    }
    #endif
}

#if canImport(GoogleMobileAds)
extension RewardedGridAccessAd: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            finishRewardFlow(earnedReward: didEarnReward)
        }
    }

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task { @MainActor in
            message = "Pub indisponible: \(error.localizedDescription)"
            finishRewardFlow(earnedReward: false)
        }
    }
}
#endif

private extension UIApplication {
    var activeRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

private struct PublishedGrid: Identifiable {
    let id: String
    let title: String
    let releaseAt: Date
    var completedPlayerCount: Int
    let crosswordGrid: CrosswordGrid?

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard let title = data["title"] as? String,
              let releaseTimestamp = data["releaseAt"] as? Timestamp else {
            return nil
        }

        self.id = document.documentID
        self.title = title
        self.releaseAt = releaseTimestamp.dateValue()
        self.completedPlayerCount = data["completedPlayerCount"] as? Int ?? 0
        self.crosswordGrid = CrosswordGrid(firestoreData: data, fallbackTitle: title)
    }

    var formattedReleaseDate: String {
        Self.releaseDateFormatter.string(from: releaseAt)
    }

    private static let releaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct CrosswordGrid {
    static let rowCount = 15
    static let columnCount = 10

    let name: String
    let placedWords: [CrosswordWord]
    let blackCells: Set<GridCoordinate>

    init?(firestoreData: [String: Any], fallbackTitle: String) {
        let payload: [String: Any]?

        if let gridMap = firestoreData["grid"] as? [String: Any] {
            payload = gridMap
        } else if let gridJSON = firestoreData["grid"] as? String,
                  let data = gridJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = object
        } else if firestoreData["placedWords"] != nil {
            payload = firestoreData
        } else {
            payload = nil
        }

        guard let payload,
              let wordsPayload = payload["placedWords"] as? [[String: Any]] else {
            return nil
        }

        self.name = (payload["name"] as? String) ?? fallbackTitle
        self.placedWords = wordsPayload.compactMap(CrosswordWord.init(payload:))
        let blackPayload = payload["blackCells"] as? [[String: Any]] ?? []
        self.blackCells = Set(blackPayload.compactMap(GridCoordinate.init(payload:)))
    }

    var definitionCells: [GridCoordinate: [CrosswordWord]] {
        Dictionary(grouping: placedWords, by: \.definitionCell)
            .mapValues { words in
                words.sorted { lhs, rhs in
                    lhs.definitionSlotPriority < rhs.definitionSlotPriority
                }
            }
    }

    var letterCellIDs: Set<GridCoordinate> {
        Set(placedWords.flatMap(\.letterCoordinates))
    }

    var solutionLetters: [GridCoordinate: String] {
        var lettersByCoordinate: [GridCoordinate: String] = [:]
        for word in placedWords {
            for (index, coordinate) in word.letterCoordinates.enumerated() where word.letters.indices.contains(index) {
                lettersByCoordinate[coordinate] = word.letters[index]
            }
        }
        return lettersByCoordinate
    }

    func correctLetter(at coordinate: GridCoordinate) -> String? {
        solutionLetters[coordinate]
    }

    func word(id: String?) -> CrosswordWord? {
        guard let id else { return nil }
        return placedWords.first { $0.id == id }
    }

    func word(containing coordinate: GridCoordinate) -> CrosswordWord? {
        placedWords.first { $0.letterCoordinates.contains(coordinate) }
    }
}

private struct CrosswordWord: Identifiable {
    let id: String
    let definitionCell: GridCoordinate
    let definitions: [String]
    let word: String
    let direction: CrosswordDirection

    nonisolated init?(payload: [String: Any]) {
        guard let id = payload["id"] as? String,
              let definitionPayload = payload["definitionCell"] as? [String: Any],
              let definitionCell = GridCoordinate(payload: definitionPayload),
              let word = payload["word"] as? String,
              let directionPayload = payload["direction"] as? [String: Any],
              let direction = CrosswordDirection(payload: directionPayload) else {
            return nil
        }

        self.id = id
        self.definitionCell = definitionCell
        self.definitions = payload["definitions"] as? [String] ?? []
        self.word = word
        self.direction = direction
    }

    var letters: [String] {
        word
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "'" }
            .map { String($0) }
    }

    var letterCoordinates: [GridCoordinate] {
        let startRow = definitionCell.row + direction.startRowDelta
        let startColumn = definitionCell.column + direction.startColumnDelta

        return letters.indices.map { index in
            GridCoordinate(
                row: startRow + index * direction.rowDelta,
                column: startColumn + index * direction.columnDelta
            )
        }
    }

    var arrowSymbol: String {
        direction.rowDelta == 1 ? "↓" : "→"
    }

    var definitionSlotPriority: Int {
        if direction.rowDelta == 0 {
            return direction.startRowDelta == 1 ? 1 : 0
        }

        return direction.startColumnDelta == 1 ? 0 : 1
    }
}

private struct CrosswordDirection {
    let rowDelta: Int
    let columnDelta: Int
    let startRowDelta: Int
    let startColumnDelta: Int

    nonisolated init?(payload: [String: Any]) {
        guard let rowDelta = payload["rowDelta"] as? Int,
              let columnDelta = payload["columnDelta"] as? Int,
              let startRowDelta = payload["startRowDelta"] as? Int,
              let startColumnDelta = payload["startColumnDelta"] as? Int else {
            return nil
        }

        self.rowDelta = rowDelta
        self.columnDelta = columnDelta
        self.startRowDelta = startRowDelta
        self.startColumnDelta = startColumnDelta
    }
}

private struct GridCoordinate: Hashable {
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    nonisolated init?(payload: [String: Any]) {
        guard let row = payload["row"] as? Int,
              let column = payload["column"] as? Int else {
            return nil
        }

        self.row = row
        self.column = column
    }
}

private struct PublicProfile: Identifiable {
    let id: String
    let uid: String
    let displayName: String
    let avatarName: String
    let isEditor: Bool
    let completedGridTitles: [String]

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        let pseudo = data["pseudo"] as? String
        let uid = (data["uid"] as? String) ?? document.documentID
        let avatarID = (data["avatarID"] as? String) ?? "08.png"
        let role = (data["role"] as? String)?.lowercased()
        let status = (data["status"] as? String)?.lowercased()

        guard let pseudo, !pseudo.isEmpty else {
            return nil
        }

        self.id = document.documentID
        self.uid = uid
        self.displayName = pseudo
        self.avatarName = avatarID.replacingOccurrences(of: ".png", with: "")
        self.isEditor = role == "editor" || status == "editor"
        self.completedGridTitles = HomeView.completedGridTitles(from: data)
    }
}

private struct HomeContent: View {
    let displayName: String
    let avatarName: String
    let isEditor: Bool
    let selectedGrid: PublishedGrid?
    let selectedGridIndex: Int
    let gridCount: Int
    let isLoadingPublishedGrids: Bool
    let gridLoadingMessage: String?
    let gridAccessMessage: String?
    let isLoadingRewardedAd: Bool
    let requiresRewardedAd: Bool
    let selectedGridIsCompleted: Bool
    let profileAction: () -> Void
    let previousGridAction: () -> Void
    let nextGridAction: () -> Void
    let playGridAction: () -> Void
    let wizzAction: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Button(action: profileAction) {
                ProfileSummaryCard(
                    displayName: displayName,
                    avatarName: avatarName,
                    isEditor: isEditor
                )
            }
            .buttonStyle(.plain)

            PublishedGridCard(
                grid: selectedGrid,
                selectedIndex: selectedGridIndex,
                gridCount: gridCount,
                isLoading: isLoadingPublishedGrids,
                message: gridLoadingMessage,
                accessMessage: gridAccessMessage,
                isLoadingRewardedAd: isLoadingRewardedAd,
                requiresRewardedAd: requiresRewardedAd,
                isCompleted: selectedGridIsCompleted,
                previousAction: previousGridAction,
                nextAction: nextGridAction,
                playAction: playGridAction
            )

            HomeNativeAdCard(adUnitID: "ca-app-pub-1003964550278910/3236151939")

            Spacer(minLength: 0)

            WizzFooter(wizzAction: wizzAction)
        }
        .padding(14)
    }
}

private struct WizzShakeEffect: GeometryEffect {
    var trigger: Int
    var animatableData: CGFloat

    init(trigger: Int) {
        self.trigger = trigger
        self.animatableData = CGFloat(trigger)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData - floor(animatableData)
        guard progress > 0 else { return ProjectionTransform(.identity) }

        let angle = progress * .pi * 18
        let decay = 1 - progress
        let x = sin(angle) * 14 * decay
        let y = cos(angle * 0.85) * 7 * decay
        let rotation = sin(angle * 0.65) * 0.018 * decay
        let transform = CGAffineTransform(translationX: x, y: y).rotated(by: rotation)
        return ProjectionTransform(transform)
    }
}

private struct WizzFooter: View {
    let wizzAction: () -> Void

    @State private var count = 0
    @State private var isSending = false

    private let endpoint = URL(string: "https://withered-mountain-e272.lrphoton-stats.workers.dev")

    var body: some View {
        Button(action: sendWizz) {
            Text("🫨 Envoyer un Wizz (\(count) envoyés)")
                .font(.xpTahoma(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(XPButtonStyle())
        .disabled(isSending)
        .opacity(isSending ? 0.55 : 1)
        .padding(10)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
        .task(loadCount)
    }

    private func loadCount() async {
        guard let endpoint else { return }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(WizzResponse.self, from: data)
            count = response.count
        } catch {
            return
        }
    }

    private func sendWizz() {
        guard let endpoint, !isSending else { return }
        wizzAction()
        let previousCount = count
        count += 1
        isSending = true

        Task {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(WizzResponse.self, from: data)
                await MainActor.run {
                    count = response.count
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    count = previousCount
                    isSending = false
                }
            }
        }
    }
}

private struct WizzResponse: Decodable {
    let count: Int
}

private struct PublicProfileListCard: View {
    let profiles: [PublicProfile]
    let isLoading: Bool
    let message: String?
    let selectAction: (PublicProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profils de test")
                .font(.custom("Tahoma", size: 13))
                .foregroundStyle(.black.opacity(0.7))

            if profiles.isEmpty {
                Text(isLoading ? "Chargement..." : (message ?? "Aucun profil public"))
                    .font(.xpTahoma(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
            } else {
                VStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        Button {
                            selectAction(profile)
                        } label: {
                            HStack(spacing: 10) {
                                AvatarBadge(name: profile.avatarName, size: 34)

                                HStack(spacing: 8) {
                                    Text(profile.displayName)
                                        .font(.xpTahoma(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                        .lineLimit(1)

                                    if profile.isEditor {
                                        EditorBadge()
                                    }
                                }

                                Spacer(minLength: 0)

                                Text(">")
                                    .font(.xpTahoma(size: 15, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.65))
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.45))
                            .overlay(Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }
}

private struct PublishedGridCard: View {
    let grid: PublishedGrid?
    let selectedIndex: Int
    let gridCount: Int
    let isLoading: Bool
    let message: String?
    let accessMessage: String?
    let isLoadingRewardedAd: Bool
    let requiresRewardedAd: Bool
    let isCompleted: Bool
    let previousAction: () -> Void
    let nextAction: () -> Void
    let playAction: () -> Void

    private var canGoToOlderGrid: Bool {
        selectedIndex + 1 < gridCount
    }

    private var canGoToNewerGrid: Bool {
        selectedIndex > 0
    }

    private var playButtonTitle: String {
        if isCompleted {
            return "Revoir"
        }

        if isLoadingRewardedAd {
            return "Chargement..."
        }

        return requiresRewardedAd ? "Jouer après pub" : "Jouer"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedIndex == 0 ? "Grille de la semaine" : "Grille précédente")
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.7))

                if let grid {
                    HStack(spacing: 8) {
                        Text(grid.title)
                            .font(.xpTahoma(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)

                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Color(red: 0.0, green: 0.56, blue: 0.18))
                                .accessibilityLabel("Grille terminee")
                        }
                    }

                    Text("Publiee le \(grid.formattedReleaseDate)")
                        .font(.custom("Tahoma", size: 13))
                        .foregroundStyle(.black.opacity(0.72))
                        .lineLimit(1)

                    Text("\(grid.completedPlayerCount) \(grid.completedPlayerCount > 1 ? "joueurs ont" : "joueur a") terminé cette grille")
                        .font(.custom("Tahoma", size: 13))
                        .foregroundStyle(.black.opacity(0.72))
                        .lineLimit(1)
                } else {
                    Text(isLoading ? "Chargement..." : (message ?? "Aucune grille publiee"))
                        .font(.xpTahoma(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: previousAction) {
                    Text("<")
                        .font(.xpTahoma(size: 18, weight: .bold))
                        .frame(width: 36, height: 30)
                }
                .buttonStyle(XPButtonStyle())
                .opacity(canGoToOlderGrid ? 1 : 0.45)
                .disabled(!canGoToOlderGrid)

                Button(playButtonTitle, action: playAction)
                    .buttonStyle(XPButtonStyle())
                    .frame(maxWidth: .infinity)
                    .opacity(grid == nil || isLoadingRewardedAd ? 0.45 : 1)
                    .disabled(grid == nil || isLoadingRewardedAd)

                Button(action: nextAction) {
                    Text(">")
                        .font(.xpTahoma(size: 18, weight: .bold))
                        .frame(width: 36, height: 30)
                }
                .buttonStyle(XPButtonStyle())
                .opacity(canGoToNewerGrid ? 1 : 0.45)
                .disabled(!canGoToNewerGrid)
            }

            if let accessMessage, !accessMessage.isEmpty {
                Text(accessMessage)
                    .font(.custom("Tahoma", size: 12))
                    .foregroundStyle(.black.opacity(0.72))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }
}

private struct GridGameContent: View {
    let grid: PublishedGrid
    let userID: String
    let backAction: () -> Void
    let completionRecorded: (String, String) -> Void

    @State private var answers: [GridCoordinate: String] = [:]
    @State private var wrongCells: Set<GridCoordinate> = []
    @State private var selectedWordID: String?
    @State private var selectedCell: GridCoordinate?
    @State private var inputIndex = 0
    @State private var elapsedSeconds = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var isCompleted = false
    @State private var completedAt: Date?

    private var selectedWord: CrosswordWord? {
        isCompleted ? nil : grid.crosswordGrid?.word(id: selectedWordID)
    }

    private var completionStatusText: String {
        guard let completedAt else { return "Grille terminée" }
        return "Grille terminée le \(Self.completionDateFormatter.string(from: completedAt))"
    }

    private static let completionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(grid.title)
                        .font(.xpTahoma(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)

                    Text("Publiée le \(grid.formattedReleaseDate)")
                        .font(.custom("Tahoma", size: 13))
                        .foregroundStyle(.black.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if !isCompleted {
                        XPToolbarIconButton(systemName: "checkmark", accessibilityLabel: "Verifier la grille") {
                            if verifyAnswers(), isGridFullyAnswered() {
                                closeKeyboard()
                                completeGrid()
                            }
                        }
                    }

                    XPToolbarIconButton(systemName: "arrow.left", accessibilityLabel: "Quitter la grille", action: backAction)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.xpPanel)
            .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
            .zIndex(2)

            if let crosswordGrid = grid.crosswordGrid {
                CrosswordBoardViewport(
                    grid: crosswordGrid,
                    answers: $answers,
                    wrongCells: wrongCells,
                    isKeyboardActive: !isCompleted && (selectedWord != nil || selectedCell != nil),
                    isReadOnly: isCompleted,
                    selectedWordID: $selectedWordID,
                    selectedCell: $selectedCell,
                    inputIndex: $inputIndex
                )
                .frame(maxHeight: .infinity)

                if !isCompleted && selectedWord == nil && selectedCell == nil {
                    GridToolsBar()
                }

                if isCompleted {
                    Text(completionStatusText)
                        .font(.xpTahoma(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.xpPanel)
                        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
                } else if let selectedWord {
                    Text((selectedWord.definitions.first ?? "DÉFINITION").uppercased())
                        .font(.xpTahoma(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.xpPanel)
                        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
                }

                if !isCompleted {
                    NativeKeyboardInput(
                        isActive: selectedWord != nil || selectedCell != nil,
                        typeLetter: typeLetter,
                        backspace: erasePreviousLetter,
                        closeKeyboard: closeKeyboard
                    )
                    .frame(width: 0, height: 0)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Grille indisponible")
                        .font(.xpTahoma(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                    Text("La grille doit contenir le JSON dans le champ grid.")
                        .font(.custom("Tahoma", size: 14))
                        .foregroundStyle(.black.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(Color.xpPanel)
                .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            loadSavedAnswers()
            loadSavedElapsedSeconds()
            loadCompletionState()
            startTimer()
        }
        .onDisappear {
            stopTimer()
            saveElapsedSeconds()
            persistTimerProgress()
        }
        .onChange(of: answers) { _, _ in
            saveAnswers()
        }
        }
    }

    private var savedAnswersKey: String {
        userScopedStorageKey(prefix: "gridAnswers")
    }

    private var savedElapsedSecondsKey: String {
        userScopedStorageKey(prefix: "gridElapsedSeconds")
    }

    private var savedCompletionKey: String {
        userScopedStorageKey(prefix: "gridCompleted")
    }

    private var savedCompletionDateKey: String {
        userScopedStorageKey(prefix: "gridCompletedAt")
    }

    private var safeUserStorageKey: String {
        userID
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    private var safeGridStorageKey: String {
        grid.id
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    private func userScopedStorageKey(prefix: String) -> String {
        "\(prefix).\(safeUserStorageKey).\(safeGridStorageKey)"
    }

    private func typeLetter(_ letter: String) {
        let normalizedLetter = String(letter.uppercased().prefix(1))
        guard !normalizedLetter.isEmpty else { return }

        if let selectedWord {
            guard selectedWord.letterCoordinates.indices.contains(inputIndex) else { return }
            let coordinate = selectedWord.letterCoordinates[inputIndex]
            answers[coordinate] = normalizedLetter
            wrongCells.remove(coordinate)

            if inputIndex + 1 < selectedWord.letterCoordinates.count {
                inputIndex += 1
            } else {
                selectedWordID = nil
                selectedCell = nil
                inputIndex = 0
            }
        } else if let selectedCell {
            answers[selectedCell] = normalizedLetter
            wrongCells.remove(selectedCell)
            self.selectedCell = nil
        }

        checkForCompletedGrid()
    }

    @discardableResult
    private func verifyAnswers() -> Bool {
        guard let crosswordGrid = grid.crosswordGrid else { return false }
        let mistakes: Set<GridCoordinate> = Set(answers.compactMap { coordinate, letter in
            guard let expectedLetter = crosswordGrid.correctLetter(at: coordinate), letter != expectedLetter else {
                return nil
            }
            return coordinate
        })

        guard !mistakes.isEmpty else { return true }
        wrongCells = mistakes

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            for coordinate in mistakes {
                answers.removeValue(forKey: coordinate)
            }
            wrongCells.subtract(mistakes)
        }

        return false
    }

    private func closeKeyboard() {
        selectedWordID = nil
        selectedCell = nil
        inputIndex = 0
        dismissNativeKeyboard()
    }

    private func dismissNativeKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func isGridFullyAnswered() -> Bool {
        guard let crosswordGrid = grid.crosswordGrid else { return false }
        let requiredCoordinates = Set(crosswordGrid.solutionLetters.keys)
        guard !requiredCoordinates.isEmpty else { return false }
        return requiredCoordinates.allSatisfy { answers[$0]?.isEmpty == false }
    }

    private func checkForCompletedGrid() {
        guard !isCompleted, isGridFullyAnswered() else { return }
        closeKeyboard()
        guard verifyAnswers() else { return }
        completeGrid()
    }

    private func completeGrid() {
        guard !isCompleted else { return }
        let finishedAt = Date()
        isCompleted = true
        completedAt = finishedAt
        selectedWordID = nil
        selectedCell = nil
        inputIndex = 0
        dismissNativeKeyboard()
        UserDefaults.standard.set(true, forKey: savedCompletionKey)
        UserDefaults.standard.set(finishedAt.timeIntervalSince1970, forKey: savedCompletionDateKey)
        saveElapsedSeconds()
        stopTimer()
        completionRecorded(grid.id, grid.title)
        persistCompletedGrid(completedAt: finishedAt)
    }

    private func startTimer() {
        guard timerTask == nil, !isCompleted else { return }
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1
                saveElapsedSeconds()
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func loadSavedElapsedSeconds() {
        elapsedSeconds = UserDefaults.standard.integer(forKey: savedElapsedSecondsKey)
    }

    private func saveElapsedSeconds() {
        UserDefaults.standard.set(elapsedSeconds, forKey: savedElapsedSecondsKey)
    }

    private func loadCompletionState() {
        isCompleted = UserDefaults.standard.bool(forKey: savedCompletionKey)
        let savedTimestamp = UserDefaults.standard.double(forKey: savedCompletionDateKey)
        completedAt = savedTimestamp > 0 ? Date(timeIntervalSince1970: savedTimestamp) : nil
        if isCompleted {
            selectedWordID = nil
            selectedCell = nil
            inputIndex = 0
        }
    }

    private func persistTimerProgress() {
        guard elapsedSeconds > 0 else { return }
        Task {
            try? await Firestore.firestore()
                .collection("users")
                .document(userID)
                .setData([
                    "gridTimers": [safeGridStorageKey: elapsedSeconds],
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        }
    }

    private func persistCompletedGrid(completedAt: Date) {
        let completedPayload: [String: Any] = [
            "gridId": grid.id,
            "title": grid.title,
            "completedAt": Timestamp(date: completedAt),
            "elapsedSeconds": elapsedSeconds
        ]

        Task {
            do {
                let database = Firestore.firestore()
                try await database.collection("users").document(userID).setData([
                    "completedGrids": [safeGridStorageKey: completedPayload],
                    "completedGridTitles": FieldValue.arrayUnion([grid.title]),
                    "gridTimers": [safeGridStorageKey: elapsedSeconds],
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            } catch {
                return
            }
        }
    }

    private func erasePreviousLetter() {
        if let selectedWord {
            guard !selectedWord.letterCoordinates.isEmpty else { return }
            let currentCoordinate = selectedWord.letterCoordinates[min(inputIndex, selectedWord.letterCoordinates.count - 1)]
            let targetIndex: Int

            if answers[currentCoordinate] != nil {
                targetIndex = inputIndex
            } else {
                targetIndex = max(inputIndex - 1, 0)
            }

            let targetCoordinate = selectedWord.letterCoordinates[targetIndex]
            answers.removeValue(forKey: targetCoordinate)
            inputIndex = targetIndex
        } else if let selectedCell {
            answers.removeValue(forKey: selectedCell)
        }
    }

    private func loadSavedAnswers() {
        guard let savedAnswers = UserDefaults.standard.dictionary(forKey: savedAnswersKey) as? [String: String] else {
            return
        }

        answers = Dictionary(uniqueKeysWithValues: savedAnswers.compactMap { key, value in
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let row = Int(parts[0]),
                  let column = Int(parts[1]) else {
                return nil
            }

            return (GridCoordinate(row: row, column: column), value)
        })
    }

    private func saveAnswers() {
        let encodedAnswers = Dictionary(uniqueKeysWithValues: answers.map { coordinate, letter in
            ("\(coordinate.row),\(coordinate.column)", letter)
        })
        UserDefaults.standard.set(encodedAnswers, forKey: savedAnswersKey)
    }
}

private struct GridToolsBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Button("Index") {}
                .buttonStyle(XPButtonStyle())
                .disabled(true)
                .opacity(0.45)

            Button("Lettre hasard") {}
                .buttonStyle(XPButtonStyle())
                .disabled(true)
                .opacity(0.45)

            Button("Choisir lettre") {}
                .buttonStyle(XPButtonStyle())
                .disabled(true)
                .opacity(0.45)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }
}

private struct CrosswordBoardViewport: View {
    let grid: CrosswordGrid
    @Binding var answers: [GridCoordinate: String]
    let wrongCells: Set<GridCoordinate>
    let isKeyboardActive: Bool
    let isReadOnly: Bool
    @Binding var selectedWordID: String?
    @Binding var selectedCell: GridCoordinate?
    @Binding var inputIndex: Int

    @State private var scale: CGFloat = 0.82
    @State private var lastScale: CGFloat = 0.82
    @State private var offset: CGSize = .zero
    @State private var dragStartOffset: CGSize?

    private let cellSize: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.xpPanel

                CrosswordBoard(
                    grid: grid,
                    cellSize: cellSize,
                    answers: $answers,
                    wrongCells: wrongCells,
                    isReadOnly: isReadOnly,
                    selectedWordID: $selectedWordID,
                    selectedCell: $selectedCell,
                    inputIndex: $inputIndex
                )
                .frame(
                    width: CGFloat(CrosswordGrid.columnCount) * cellSize,
                    height: CGFloat(CrosswordGrid.rowCount) * cellSize
                )
                .scaleEffect(scale)
                .offset(offset)
                .gesture(boardGesture(in: proxy.size))
            }
            .clipped()
            .overlay(Rectangle().stroke(Color.black.opacity(0.45), lineWidth: 1))
            .onAppear {
                configureInitialScale(in: proxy.size)
            }
            .onChange(of: selectedWordID) { _, _ in
                updateSelectionViewport(in: proxy.size)
            }
            .onChange(of: selectedCell) { _, _ in
                updateSelectionViewport(in: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                if selectedWordID == nil && selectedCell == nil {
                    configureInitialScale(in: newSize)
                } else {
                    focusSelection(in: newSize)
                }
            }
        }
        .background(Color.xpPanel)
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }

    private func boardGesture(in size: CGSize) -> some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                let start = dragStartOffset ?? offset
                dragStartOffset = start
                offset = clampedOffset(
                    CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                    scale: scale,
                    viewport: effectiveViewport(for: size)
                )
            }
            .onEnded { _ in
                dragStartOffset = nil
                offset = clampedOffset(offset, scale: scale, viewport: effectiveViewport(for: size))
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minimumScale(in: size)), 1.55)
                offset = clampedOffset(offset, scale: scale, viewport: effectiveViewport(for: size))
            }
            .onEnded { _ in
                lastScale = scale
                offset = clampedOffset(offset, scale: scale, viewport: effectiveViewport(for: size))
            }

        return drag.simultaneously(with: magnify)
    }

    private func configureInitialScale(in size: CGSize) {
        let fitWidth = max(size.width - 28, 0) / (CGFloat(CrosswordGrid.columnCount) * cellSize)
        let fitHeight = max(size.height - 28, 0) / (CGFloat(CrosswordGrid.rowCount) * cellSize)
        let fittedScale = min(fitWidth, fitHeight)
        let initialScale = min(max(fittedScale, minimumScale(in: size)), 1.0)
        scale = initialScale
        lastScale = initialScale
        offset = .zero
    }

    private func updateSelectionViewport(in size: CGSize) {
        if selectedWordID == nil && selectedCell == nil {
            configureInitialScale(in: size)
        } else {
            focusSelection(in: size)
        }
    }

    private func focusSelection(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let viewport = effectiveViewport(for: size)

        if let word = grid.word(id: selectedWordID) {
            focus(coordinates: word.letterCoordinates, isVertical: word.direction.rowDelta != 0, viewport: viewport)
        } else if let selectedCell {
            focus(coordinates: [selectedCell], isVertical: false, viewport: viewport)
        }
    }

    private func focus(coordinates: [GridCoordinate], isVertical: Bool, viewport: CGSize) {
        guard let firstRow = coordinates.map(\.row).min(),
              let lastRow = coordinates.map(\.row).max(),
              let firstColumn = coordinates.map(\.column).min(),
              let lastColumn = coordinates.map(\.column).max() else {
            return
        }

        let spanColumns = CGFloat(lastColumn - firstColumn + 1)
        let spanRows = CGFloat(lastRow - firstRow + 1)
        let desiredScale: CGFloat

        if isVertical {
            desiredScale = (viewport.height * 0.86) / max(spanRows * cellSize, cellSize)
        } else {
            desiredScale = (viewport.width * 0.86) / max(spanColumns * cellSize, cellSize)
        }

        let newScale = min(max(desiredScale, minimumScale(in: viewport)), 1.55)
        let boardWidth = CGFloat(CrosswordGrid.columnCount) * cellSize
        let boardHeight = CGFloat(CrosswordGrid.rowCount) * cellSize
        let centerColumn = (CGFloat(firstColumn + lastColumn) + 1) / 2
        let centerRow = (CGFloat(firstRow + lastRow) + 1) / 2
        let proposedOffset = CGSize(
            width: -((centerColumn * cellSize) - boardWidth / 2) * newScale,
            height: -((centerRow * cellSize) - boardHeight / 2) * newScale
        )

        scale = newScale
        lastScale = newScale
        offset = clampedOffset(proposedOffset, scale: newScale, viewport: viewport)
    }

    private func effectiveViewport(for size: CGSize) -> CGSize {
        guard isKeyboardActive else { return size }
        return CGSize(width: size.width, height: max(size.height - 310, 180))
    }

    private func minimumScale(in size: CGSize) -> CGFloat {
        let fitWidth = max(size.width - 28, 0) / (CGFloat(CrosswordGrid.columnCount) * cellSize)
        let fitHeight = max(size.height - 28, 0) / (CGFloat(CrosswordGrid.rowCount) * cellSize)
        return min(max(min(fitWidth, fitHeight) * 0.82, 0.58), 0.9)
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let boardWidth = CGFloat(CrosswordGrid.columnCount) * cellSize * scale
        let boardHeight = CGFloat(CrosswordGrid.rowCount) * cellSize * scale
        let maxX = max((boardWidth - viewport.width) / 2, 0)
        let maxY = max((boardHeight - viewport.height) / 2 + (isKeyboardActive ? 90 : 16), 0)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

private struct CrosswordBoard: View {
    let grid: CrosswordGrid
    let cellSize: CGFloat
    @Binding var answers: [GridCoordinate: String]
    let wrongCells: Set<GridCoordinate>
    let isReadOnly: Bool
    @Binding var selectedWordID: String?
    @Binding var selectedCell: GridCoordinate?
    @Binding var inputIndex: Int

    private var selectedWord: CrosswordWord? {
        isReadOnly ? nil : grid.word(id: selectedWordID)
    }

    private var selectedCoordinates: Set<GridCoordinate> {
        guard !isReadOnly else { return [] }
        var coordinates = Set(selectedWord?.letterCoordinates ?? [])
        if let selectedCell {
            coordinates.insert(selectedCell)
        }
        return coordinates
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<CrosswordGrid.rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<CrosswordGrid.columnCount, id: \.self) { column in
                        let coordinate = GridCoordinate(row: row, column: column)
                        CrosswordCell(
                            coordinate: coordinate,
                            definitionWords: grid.definitionCells[coordinate] ?? [],
                            selectedWordID: selectedWordID,
                            letter: letter(at: coordinate),
                            isSelected: selectedCoordinates.contains(coordinate),
                            isWrong: !isReadOnly && wrongCells.contains(coordinate),
                            isBlack: grid.blackCells.contains(coordinate),
                            isReadOnly: isReadOnly,
                            cellSize: cellSize,
                            selectWord: selectWord,
                            selectCell: selectCell
                        )
                    }
                }
            }
        }
        .background(Color.white)
    }

    private func selectWord(_ word: CrosswordWord) {
        guard !isReadOnly else { return }
        selectedWordID = word.id
        selectedCell = nil
        inputIndex = firstEmptyIndex(for: word)
    }

    private func selectCell(_ coordinate: GridCoordinate) {
        guard !isReadOnly else { return }
        selectedWordID = nil
        selectedCell = coordinate
        inputIndex = 0
    }

    private func firstEmptyIndex(for word: CrosswordWord) -> Int {
        word.letterCoordinates.firstIndex { answers[$0] == nil } ?? 0
    }

    private func letter(at coordinate: GridCoordinate) -> String {
        answers[coordinate] ?? ""
    }
}

private struct CrosswordCell: View {
    let coordinate: GridCoordinate
    let definitionWords: [CrosswordWord]
    let selectedWordID: String?
    let letter: String
    let isSelected: Bool
    let isWrong: Bool
    let isBlack: Bool
    let isReadOnly: Bool
    let cellSize: CGFloat
    let selectWord: (CrosswordWord) -> Void
    let selectCell: (GridCoordinate) -> Void

    private var isDefinition: Bool {
        !definitionWords.isEmpty
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)

            if isDefinition {
                VStack(spacing: 0) {
                    ForEach(definitionWords) { word in
                        DefinitionCellSegment(
                            word: word,
                            isSelected: !isReadOnly && word.id == selectedWordID,
                            isReadOnly: isReadOnly
                        ) {
                            selectWord(word)
                        }
                    }
                }
            } else if !isBlack {
                Text(letter)
                    .font(.xpTahoma(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isReadOnly else { return }
                        selectCell(coordinate)
                    }
            }
        }
        .frame(width: cellSize, height: cellSize)
        .overlay(Rectangle().stroke(Color.black.opacity(0.72), lineWidth: 0.8))
    }

    private var backgroundColor: Color {
        if isBlack {
            return .black
        }

        if isDefinition {
            return Color(red: 1.0, green: 0.95, blue: 0.72)
        }

        if isWrong {
            return Color(red: 1.0, green: 0.55, blue: 0.52)
        }

        return isSelected ? Color(red: 0.73, green: 0.95, blue: 0.74) : .white
    }
}

private struct DefinitionCellSegment: View {
    let word: CrosswordWord
    let isSelected: Bool
    let isReadOnly: Bool
    let action: () -> Void

    private var definitionText: String {
        let text = word.definitions.joined(separator: " / ").uppercased()
        return text.isEmpty ? " " : text
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(definitionText)
                    .font(.xpTahoma(size: 6.5, weight: .bold))
                    .foregroundStyle(.black.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)

                Text(word.arrowSymbol)
                    .font(.xpTahoma(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.0, green: 0.2, blue: 0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color(red: 0.73, green: 0.95, blue: 0.74) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .overlay(Rectangle().stroke(Color.black.opacity(isSelected ? 0.55 : 0.18), lineWidth: isSelected ? 1 : 0.5))
    }
}

private struct NativeKeyboardInput: UIViewRepresentable {
    let isActive: Bool
    let typeLetter: (String) -> Void
    let backspace: () -> Void
    let closeKeyboard: () -> Void

    func makeUIView(context: Context) -> KeyboardTextField {
        let textField = KeyboardTextField()
        textField.keyboardType = .asciiCapable
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.returnKeyType = .done
        textField.textContentType = nil
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.tintColor = .clear
        textField.textColor = .clear
        textField.backgroundColor = .clear
        textField.delegate = context.coordinator
        textField.deleteBackwardHandler = backspace
        return textField
    }

    func updateUIView(_ uiView: KeyboardTextField, context: Context) {
        context.coordinator.typeLetter = typeLetter
        context.coordinator.backspace = backspace
        context.coordinator.closeKeyboard = closeKeyboard
        uiView.deleteBackwardHandler = backspace

        if isActive, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isActive, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            typeLetter: typeLetter,
            backspace: backspace,
            closeKeyboard: closeKeyboard
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var typeLetter: (String) -> Void
        var backspace: () -> Void
        var closeKeyboard: () -> Void

        init(
            typeLetter: @escaping (String) -> Void,
            backspace: @escaping () -> Void,
            closeKeyboard: @escaping () -> Void
        ) {
            self.typeLetter = typeLetter
            self.backspace = backspace
            self.closeKeyboard = closeKeyboard
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string == "\n" {
                closeKeyboard()
            } else if string.isEmpty {
                backspace()
            } else if let character = string.uppercased().first, character.isLetter {
                typeLetter(String(character))
            }

            textField.text = ""
            return false
        }
    }

    final class KeyboardTextField: UITextField {
        var deleteBackwardHandler: (() -> Void)?

        override var textInputContextIdentifier: String? {
            nil
        }

        override func deleteBackward() {
            deleteBackwardHandler?()
            super.deleteBackward()
        }
    }
}

private struct ProfileSummaryCard: View {
    let displayName: String
    let avatarName: String
    let isEditor: Bool
    var eyebrow = "Bienvenue"

    var body: some View {
        HStack(spacing: 14) {
            AvatarBadge(name: avatarName)

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.7))
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.xpTahoma(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)

                    if isEditor {
                        EditorBadge()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }
}

private struct PublicProfileContent: View {
    let displayName: String
    let avatarName: String
    let isEditor: Bool
    let completedGridTitles: [String]
    let backAction: () -> Void
    var settingsAction: (() -> Void)? = nil
    var contactAction: () -> Void


    var body: some View {
        ZStack {
            VStack(spacing: 18) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    AvatarBadge(name: avatarName, size: 112)

                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text(displayName)
                                .font(.xpTahoma(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                                .lineLimit(1)

                            if isEditor {
                                EditorBadge()
                            }
                        }

                    }
                }
                .frame(maxWidth: .infinity)
                .padding(18)

                VStack(spacing: 8) {
                    XPToolbarIconButton(systemName: "arrow.left", accessibilityLabel: "Retour", action: backAction)

                    if let settingsAction {
                        XPToolbarIconButton(systemName: "gearshape.fill", accessibilityLabel: "Reglages du profil", action: settingsAction)
                        XPToolbarIconButton(text: "?", accessibilityLabel: "Contacter le support", action: contactAction)
                    }
                }
                .padding(8)
            }
            .background(Color.xpPanel)
            .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))

            VStack(alignment: .leading, spacing: 10) {
                Text("Grilles terminées")
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.7))

                if completedGridTitles.isEmpty {
                    Text("Aucune grille terminée")
                        .font(.xpTahoma(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                } else {
                    ForEach(completedGridTitles, id: \.self) { title in
                        Text(title)
                            .font(.xpTahoma(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.white.opacity(0.45))
                            .overlay(Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 1))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.xpPanel)
            .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))

            Spacer(minLength: 0)
        }
        .padding(14)
        }
    }
}

private struct ProfileInfoWindow: View {
    let closeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Informations")
                    .font(.xpTahoma(size: 18, weight: .bold))
                    .foregroundStyle(.black)

                Spacer(minLength: 0)

                Button("X", action: closeAction)
                    .buttonStyle(XPButtonStyle(foregroundColor: .red))
                    .frame(width: 42)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Flèche-moi ça")
                    .font(.xpTahoma(size: 15, weight: .bold))
                    .foregroundStyle(.black)

                Text("Les profils publics affichent le pseudo, l'avatar, le statut Éditeur quand il existe, et les grilles terminées. Les données privées du compte restent dans ton espace utilisateur.")
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Pour toute question légale, confidentialité ou suppression de données, contacte-nous par e-mail.")
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Nous contacter", action: openContactMail)
                .buttonStyle(XPButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
        .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 5)
    }

    private func openContactMail() {
        guard let url = URL(string: "mailto:contact@flechemoica.fr") else { return }
        UIApplication.shared.open(url)
    }
}

private struct ProfileSettingsContent: View {
    private static let avatarNames = ["01", "02", "03", "04", "05", "06", "07", "08", "09"]

    let user: User
    let initialDisplayName: String
    let initialEmail: String
    let initialAvatarName: String
    let backAction: () -> Void
    let userChanged: (User) -> Void
    let deletingAccountChanged: (Bool) -> Void
    let signedOut: () -> Void

    private enum SettingsPanel: Identifiable {
        case displayName
        case avatar
        case email
        case password
        case deleteAccount

        var id: String {
            switch self {
            case .displayName: return "displayName"
            case .avatar: return "avatar"
            case .email: return "email"
            case .password: return "password"
            case .deleteAccount: return "deleteAccount"
            }
        }

        var title: String {
            switch self {
            case .displayName: return "Modifier le pseudo"
            case .avatar: return "Changer d'avatar"
            case .email: return "Changer l'e-mail"
            case .password: return "Changer le mot de passe"
            case .deleteAccount: return "Supprimer le compte"
            }
        }
    }

    @State private var displayName: String
    @State private var selectedAvatarIndex: Int
    @State private var savedDisplayName: String
    @State private var savedEmail: String
    @State private var savedAvatarName: String
    @State private var currentPassword = ""
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var statusText = ""
    @State private var isSubmitting = false
    @State private var isShowingDeleteConfirmation = false
    @State private var activePanel: SettingsPanel?
    @State private var appleSignInCoordinator: ProfileAppleSignInCoordinator?

    init(
        user: User,
        initialDisplayName: String,
        initialEmail: String,
        initialAvatarName: String,
        backAction: @escaping () -> Void,
        userChanged: @escaping (User) -> Void,
        deletingAccountChanged: @escaping (Bool) -> Void,
        signedOut: @escaping () -> Void
    ) {
        self.user = user
        self.initialDisplayName = initialDisplayName
        self.initialEmail = initialEmail
        self.initialAvatarName = initialAvatarName
        self.backAction = backAction
        self.userChanged = userChanged
        self.deletingAccountChanged = deletingAccountChanged
        self.signedOut = signedOut
        _displayName = State(initialValue: initialDisplayName)
        _selectedAvatarIndex = State(initialValue: Self.avatarNames.firstIndex(of: initialAvatarName) ?? 0)
        _savedDisplayName = State(initialValue: initialDisplayName)
        _savedEmail = State(initialValue: initialEmail)
        _savedAvatarName = State(initialValue: initialAvatarName)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayNameKey: String {
        trimmedDisplayName.lowercased()
    }

    private var savedDisplayNameKey: String {
        savedDisplayName.lowercased()
    }

    private var selectedAvatarName: String {
        Self.avatarNames[selectedAvatarIndex]
    }

    private var selectedAvatarID: String {
        "\(selectedAvatarName).png"
    }

    private var selectedAvatarURL: URL? {
        URL(string: "flechemoica-avatar://\(selectedAvatarID)")
    }

    private var hasAccountChanges: Bool {
        displayNameKey != savedDisplayNameKey
    }

    private var hasAvatarChanges: Bool {
        selectedAvatarName != savedAvatarName
    }

    private var wantsPasswordChange: Bool {
        !newPassword.isEmpty || !confirmPassword.isEmpty
    }

    private var trimmedNewEmail: String {
        newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canChangeEmail: Bool {
        !isSubmitting
            && currentPassword.count >= 6
            && trimmedNewEmail.contains("@")
            && trimmedNewEmail.lowercased() != savedEmail.lowercased()
    }

    private var canSave: Bool {
        guard !isSubmitting else { return false }
        guard !trimmedDisplayName.isEmpty else { return false }
        guard hasAccountChanges || hasAvatarChanges || wantsPasswordChange else { return false }

        if wantsPasswordChange {
            return currentPassword.count >= 6 && newPassword.count >= 6 && newPassword == confirmPassword
        }

        return true
    }

    private var isAppleAccount: Bool {
        user.providerData.contains { $0.providerID == "apple.com" }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let visibleVersion: String
        if let version, !version.isEmpty {
            visibleVersion = version
        } else {
            visibleVersion = "1.0"
        }

        if let build, !build.isEmpty, build != visibleVersion {
            return "Version \(visibleVersion) (\(build))"
        }

        return "Version \(visibleVersion)"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                SettingsSectionTitle("Compte")
                                Spacer(minLength: 0)
                                XPToolbarIconButton(systemName: "arrow.left", accessibilityLabel: "Retour", action: backAction)
                                    .disabled(isSubmitting)
                            }
                            SettingsMenuButton(title: "Modifier le pseudo") {
                                activePanel = .displayName
                            }
                            SettingsMenuButton(title: "Changer d'avatar") {
                                activePanel = .avatar
                            }
                            SettingsMenuButton(title: "Changer l'e-mail") {
                                activePanel = .email
                            }
                            SettingsMenuButton(title: "Changer le mot de passe") {
                                activePanel = .password
                            }
                        }
                        .settingsPanel()

                        VStack(alignment: .leading, spacing: 14) {
                            SettingsSectionTitle("Confidentialité")
                            SettingsMenuButton(title: "Supprimer le compte", isDestructive: true) {
                                activePanel = .deleteAccount
                            }
                        }
                        .settingsPanel()

                        appVersionBadge

                        if !statusText.isEmpty {
                            Text(statusText)
                                .font(.custom("Tahoma", size: 13))
                                .foregroundStyle(.black.opacity(0.78))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }
                    }

                    Button("Déconnexion") {
                        signOutTapped()
                    }
                    .buttonStyle(XPButtonStyle(foregroundColor: .red))
                    .disabled(isSubmitting)
                }
                .padding(14)

                SettingsLegalFooter()
            }

            if let activePanel {
                SettingsDetailWindow(title: activePanel.title) {
                    self.activePanel = nil
                } content: {
                    panelContent(for: activePanel)
                }
            }

            if isShowingDeleteConfirmation {
                DeleteAccountConfirmationWindow(
                    cancelAction: {
                        isShowingDeleteConfirmation = false
                    },
                    confirmAction: {
                        isShowingDeleteConfirmation = false
                        deleteAccountTapped()
                    }
                )
            }
        }
    }

    private var appVersionBadge: some View {
        Text(appVersionText)
            .font(.custom("Tahoma", size: 12))
            .foregroundStyle(.black.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func panelContent(for panel: SettingsPanel) -> some View {
        switch panel {
        case .displayName:
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle("Pseudo actuel")
                ProfileReadOnlyField(text: savedDisplayName, prompt: "Pseudo")
                ProfileTextField(text: $displayName, prompt: "Nouveau pseudo")
                savePanelButton(title: "Enregistrer")
            }
        case .avatar:
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle("Avatar actuel")
                ProfileAvatarPickerRow(
                    avatarName: selectedAvatarName,
                    previousAction: selectPreviousAvatar,
                    nextAction: selectNextAvatar
                )
                savePanelButton(title: "Enregistrer")
            }
        case .email:
            VStack(alignment: .leading, spacing: 12) {
                ProfileReadOnlyField(text: savedEmail, prompt: "E-mail")
                ProfileTextField(text: $newEmail, prompt: "Nouvel e-mail", keyboard: .emailAddress, textContentType: .emailAddress)
                ProfileSecureField(text: $currentPassword, prompt: "Mot de passe", textContentType: .oneTimeCode)
                Button(isSubmitting ? "Enregistrement..." : "Changer l'e-mail") {
                    changeEmailTapped()
                }
                .buttonStyle(XPButtonStyle())
                .opacity(canChangeEmail ? 1 : 0.55)
                .disabled(!canChangeEmail)
                .frame(maxWidth: .infinity)
            }
        case .password:
            VStack(alignment: .leading, spacing: 12) {
                ProfileSecureField(text: $currentPassword, prompt: "Ancien mot de passe", textContentType: .oneTimeCode)
                ProfileSecureField(text: $newPassword, prompt: "Nouveau mot de passe", textContentType: .oneTimeCode)
                ProfileSecureField(text: $confirmPassword, prompt: "Confirmation", textContentType: .oneTimeCode)
                savePanelButton(title: "Changer le mot de passe")
            }
        case .deleteAccount:
            VStack(alignment: .leading, spacing: 12) {
                SettingsTextPanel(lines: [
                    "Cette action supprime définitivement le compte.",
                    isAppleAccount ? "Une confirmation Apple sera demandee pour supprimer le compte." : "Entre ton mot de passe actuel pour confirmer."
                ])
                if !isAppleAccount {
                    ProfileSecureField(text: $currentPassword, prompt: "Ancien mot de passe", textContentType: .oneTimeCode)
                }
                Button("Supprimer le compte") {
                    requestAccountDeletionConfirmation()
                }
                .buttonStyle(XPButtonStyle(foregroundColor: .red))
                .disabled(isSubmitting)
            }
        }
    }

    private func savePanelButton(title: String) -> some View {
        Button(isSubmitting ? "Enregistrement..." : title) {
            saveTapped()
        }
        .buttonStyle(XPButtonStyle())
        .opacity(canSave ? 1 : 0.55)
        .disabled(!canSave)
        .frame(maxWidth: .infinity)
    }

    private func saveTapped() {
        guard canSave else {
            statusText = "Verifie les champs avant d'enregistrer."
            return
        }

        isSubmitting = true
        statusText = "Enregistrement..."

        Task {
            do {
                try await validateProfileAvailability()

                if wantsPasswordChange {
                    try await reauthenticateUser()
                }

                if hasAccountChanges || hasAvatarChanges {
                    let request = user.createProfileChangeRequest()
                    request.displayName = trimmedDisplayName
                    request.photoURL = selectedAvatarURL
                    try await request.commitChanges()
                }

                if wantsPasswordChange {
                    try await user.updatePassword(to: newPassword)
                }

                let currentEmail = Auth.auth().currentUser?.email ?? savedEmail
                try await saveUserDocument(
                    email: currentEmail,
                    emailKey: currentEmail.lowercased()
                )
                try await user.reload()

                await MainActor.run {
                    isSubmitting = false
                    savedDisplayName = trimmedDisplayName
                    savedEmail = currentEmail
                    savedAvatarName = selectedAvatarName
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                    statusText = ""
                    userChanged(Auth.auth().currentUser ?? user)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    statusText = firebaseMessage(for: error)
                }
            }
        }
    }

    private func changeEmailTapped() {
        guard canChangeEmail else {
            statusText = "Verifie le nouvel e-mail et l'ancien mot de passe."
            return
        }

        isSubmitting = true
        statusText = "Changement de l'e-mail..."

        Task {
            do {
                try await reauthenticateUser()
                try await user.sendEmailVerification(beforeUpdatingEmail: trimmedNewEmail)

                await MainActor.run {
                    isSubmitting = false
                    newEmail = ""
                    currentPassword = ""
                    statusText = "E-mail de verification envoye. Valide-le pour changer l'adresse."
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    statusText = firebaseMessage(for: error)
                }
            }
        }
    }

    private func requestAccountDeletionConfirmation() {
        guard isAppleAccount || currentPassword.count >= 6 else {
            statusText = "Entre ton ancien mot de passe avant de supprimer le compte."
            return
        }

        statusText = ""
        isShowingDeleteConfirmation = true
    }

    private func signOutTapped() {
        do {
            try Auth.auth().signOut()
            signedOut()
        } catch {
            statusText = firebaseMessage(for: error)
        }
    }

    private func deleteAccountTapped() {
        guard isAppleAccount || currentPassword.count >= 6 else {
            statusText = "Entre ton ancien mot de passe pour supprimer le compte."
            return
        }

        isSubmitting = true
        statusText = "Suppression du compte..."
        deletingAccountChanged(true)

        Task {
            var appleAuthorizationCode: String?
            var firebaseDeletionIDToken: String?
            var shouldForceSignOut = false

            do {
                if isAppleAccount {
                    let appleDeletionContext = try await appleDeletionContext()
                    try await user.reauthenticate(with: appleDeletionContext.credential)
                    appleAuthorizationCode = appleDeletionContext.authorizationCode
                } else {
                    try await reauthenticateUser()
                }

                let userToDelete = Auth.auth().currentUser ?? user
                if let appleAuthorizationCode {
                    firebaseDeletionIDToken = try await userToDelete.getIDTokenResult(forcingRefresh: true).token
                    try await revokeAppleAuthorization(authorizationCode: appleAuthorizationCode)
                    print("Apple Sign in authorization revoked.")
                }

                try await deleteUserDocuments()
                shouldForceSignOut = true
                try await deleteFirebaseAuthUser(userToDelete, fallbackIDToken: firebaseDeletionIDToken)
                try? Auth.auth().signOut()

                await MainActor.run {
                    signedOut()
                }
            } catch {
                print("Account deletion failed: \(error)")
                await MainActor.run {
                    if shouldForceSignOut {
                        try? Auth.auth().signOut()
                        signedOut()
                    } else {
                        deletingAccountChanged(false)
                        isSubmitting = false
                        statusText = firebaseMessage(for: error)
                    }
                }
            }
        }
    }

    private func revokeAppleAuthorization(authorizationCode: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Auth.auth().revokeToken(withAuthorizationCode: authorizationCode) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteFirebaseAuthUser(_ userToDelete: User, fallbackIDToken: String?) async throws {
        do {
            try await userToDelete.delete()
            print("Firebase Auth user deleted: \(userToDelete.uid)")
        } catch {
            guard let fallbackIDToken else {
                throw error
            }

            print("Firebase Auth SDK deletion failed, retrying with REST: \(error)")
            try await deleteFirebaseAuthUserWithREST(idToken: fallbackIDToken)
            print("Firebase Auth user deleted with REST fallback: \(userToDelete.uid)")
        }
    }

    private func deleteFirebaseAuthUserWithREST(idToken: String) async throws {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String,
              let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=\(apiKey)") else {
            throw ProfileSettingsError.missingFirebaseAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": idToken])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ProfileSettingsError.firebaseRESTDeletionFailed
        }
    }

    private func selectPreviousAvatar() {
        selectedAvatarIndex = selectedAvatarIndex == 0 ? Self.avatarNames.count - 1 : selectedAvatarIndex - 1
    }

    private func selectNextAvatar() {
        selectedAvatarIndex = (selectedAvatarIndex + 1) % Self.avatarNames.count
    }

    private func reauthenticateUser() async throws {
        let credential = EmailAuthProvider.credential(withEmail: savedEmail, password: currentPassword)
        try await user.reauthenticate(with: credential)
    }

    private func appleDeletionContext() async throws -> AppleDeletionContext {
        let nonce = randomNonceString()
        let appleIDCredential = try await requestAppleCredential(nonce: nonce)

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw ProfileSettingsError.missingAppleIdentityToken
        }
        guard let authorizationCode = appleIDCredential.authorizationCode,
              let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
            throw ProfileSettingsError.missingAppleAuthorizationCode
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        return AppleDeletionContext(
            credential: credential,
            authorizationCode: authorizationCodeString
        )
    }

    private func requestAppleCredential(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)

                let coordinator = ProfileAppleSignInCoordinator(
                    onSuccess: { credential in
                        appleSignInCoordinator = nil
                        continuation.resume(returning: credential)
                    },
                    onFailure: { error in
                        appleSignInCoordinator = nil
                        continuation.resume(throwing: error)
                    }
                )

                appleSignInCoordinator = coordinator

                let authorizationController = ASAuthorizationController(authorizationRequests: [request])
                authorizationController.delegate = coordinator
                authorizationController.presentationContextProvider = coordinator
                authorizationController.performRequests()
            }
        }
    }

    private func validateProfileAvailability() async throws {
        let database = Firestore.firestore()

        if displayNameKey != savedDisplayNameKey {
            let profileKeySnapshot = try await database
                .collection("users")
                .whereField("pseudoKey", isEqualTo: displayNameKey)
                .limit(to: 1)
                .getDocuments()
            let profileSnapshot = try await database
                .collection("users")
                .whereField("pseudo", isEqualTo: trimmedDisplayName)
                .limit(to: 1)
                .getDocuments()

            if profileKeySnapshot.documents.contains(where: { $0.documentID != user.uid }) ||
                profileSnapshot.documents.contains(where: { $0.documentID != user.uid }) {
                throw ProfileSettingsError.displayNameAlreadyTaken
            }
        }

    }

    private func saveUserDocument(email: String, emailKey: String) async throws {
        let database = Firestore.firestore()
        let updates: [String: Any] = [
            "uid": user.uid,
            "email": email,
            "emailKey": emailKey,
            "pseudo": trimmedDisplayName,
            "pseudoKey": displayNameKey,
            "avatarID": selectedAvatarID,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await database
            .collection("users")
            .document(user.uid)
            .setData(updates, merge: true)
    }

    private func deleteUserDocuments() async throws {
        let database = Firestore.firestore()
        try await database.collection("users").document(user.uid).delete()
    }

    private func firebaseMessage(for error: Error) -> String {
        if let profileError = error as? ProfileSettingsError {
            return profileError.message
        }

        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            return "Confirmation Apple annulee."
        }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           nsError.code == AuthErrorCode.operationNotAllowed.rawValue,
           nsError.localizedDescription.contains("Code flow is not enabled for Apple") {
            return "La revocation Apple n'est pas configuree dans Firebase."
        }

        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return nsError.localizedDescription
        }

        switch code {
        case .emailAlreadyInUse:
            return "Cet e-mail a deja un compte."
        case .invalidEmail:
            return "E-mail invalide."
        case .wrongPassword, .invalidCredential:
            return "Ancien mot de passe incorrect."
        case .requiresRecentLogin:
            return "Reconnecte-toi puis reessaie cette action."
        case .tooManyRequests:
            return "Trop de tentatives. Reessaie plus tard."
        case .networkError:
            return "Probleme reseau. Reessaie."
        case .weakPassword:
            return "Nouveau mot de passe trop faible."
        default:
            return nsError.localizedDescription
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)

        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

            if status != errSecSuccess {
                fatalError("Impossible de generer le nonce Apple.")
            }

            randomBytes.forEach { randomByte in
                if remainingLength == 0 {
                    return
                }

                if randomByte < charset.count {
                    result.append(charset[Int(randomByte)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)

        return hashedData.map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private enum ProfileSettingsError: Error {
    case displayNameAlreadyTaken
    case missingAppleIdentityToken
    case missingAppleAuthorizationCode
    case missingFirebaseAPIKey
    case firebaseRESTDeletionFailed

    var message: String {
        switch self {
        case .displayNameAlreadyTaken:
            return "Ce nom d'utilisateur est deja pris."
        case .missingAppleIdentityToken:
            return "Impossible de recuperer l'identite Apple."
        case .missingAppleAuthorizationCode:
            return "Impossible de finaliser la confirmation Apple."
        case .missingFirebaseAPIKey:
            return "Configuration Firebase incomplete."
        case .firebaseRESTDeletionFailed:
            return "Suppression Firebase impossible."
        }
    }
}

private struct AppleDeletionContext {
    let credential: AuthCredential
    let authorizationCode: String
}

private final class ProfileAppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let onSuccess: (ASAuthorizationAppleIDCredential) -> Void
    let onFailure: (Error) -> Void

    init(
        onSuccess: @escaping (ASAuthorizationAppleIDCredential) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onFailure(ProfileSettingsError.missingAppleIdentityToken)
            return
        }

        onSuccess(credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onFailure(error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private struct SettingsMenuButton: View {
    let title: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(XPButtonStyle(foregroundColor: isDestructive ? .red : .black))
            .frame(maxWidth: .infinity)
    }
}

private struct XPToolbarIconButton: View {
    var systemName: String?
    var text: String?
    let accessibilityLabel: String
    var foregroundColor: Color = .black.opacity(0.78)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .bold))
                } else {
                    Text(text ?? "")
                        .font(.xpTahoma(size: 18, weight: .bold))
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(width: 34, height: 34)
            .background(Color.xpChrome)
            .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.22))
            .frame(height: 1)
            .padding(.vertical, 3)
    }
}

private struct SettingsDetailWindow<Content: View>: View {
    let title: String
    let closeAction: () -> Void
    let content: Content

    init(title: String, closeAction: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.closeAction = closeAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.xpTahoma(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Button("X", action: closeAction)
                    .buttonStyle(XPButtonStyle(foregroundColor: .red))
                    .frame(width: 42)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: 330)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
        .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 5)
        .padding(14)
    }
}

private struct DeleteAccountConfirmationWindow: View {
    let cancelAction: () -> Void
    let confirmAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supprimer définitivement ce compte ?")
                .font(.xpTahoma(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)

            Text("Le compte sera supprimé définitivement.")
                .font(.xpTahoma(size: 13))
                .foregroundStyle(.black.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Annuler", action: cancelAction)
                    .buttonStyle(XPButtonStyle())
                    .frame(maxWidth: .infinity)

                Button("Supprimer", action: confirmAction)
                    .buttonStyle(XPButtonStyle(foregroundColor: .red))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: 330)
        .background(Color.xpPanel)
        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
        .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 5)
        .padding(14)
    }
}

private struct SettingsTextPanel: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.xpTahoma(size: 14, weight: .bold))
            .foregroundStyle(.black.opacity(0.82))
    }
}

private struct ProfileAvatarPickerRow: View {
    let avatarName: String
    let previousAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("<", action: previousAction)
                .buttonStyle(XPButtonStyle())
                .frame(width: 44)

            AvatarBadge(name: avatarName)

            Button(">", action: nextAction)
                .buttonStyle(XPButtonStyle())
                .frame(width: 44)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ProfileTextField: View {
    @Binding var text: String
    var prompt: String
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType?

    var body: some View {
        TextField(text: $text) {
            Text(prompt)
                .foregroundStyle(.gray)
        }
        .textInputAutocapitalization(.never)
        .keyboardType(keyboard)
        .textContentType(textContentType)
        .autocorrectionDisabled()
        .profileInputStyle()
    }
}

private struct ProfileReadOnlyField: View {
    let text: String
    let prompt: String

    var body: some View {
        Text(text.isEmpty ? prompt : text)
            .font(.custom("Tahoma", size: 16))
            .foregroundStyle(.black.opacity(text.isEmpty ? 0.42 : 0.58))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(Color(red: 0.88, green: 0.88, blue: 0.86))
            .overlay(Rectangle().stroke(Color.black.opacity(0.24), lineWidth: 2))
    }
}

private struct ProfileSecureField: View {
    @Binding var text: String
    var prompt: String
    var textContentType: UITextContentType? = .password

    var body: some View {
        SecurePasswordTextField(
            text: $text,
            placeholder: prompt,
            textContentType: textContentType
        )
        .profileInputStyle()
    }
}

private struct SettingsLegalFooter: View {
    private let legalNoticeURL = URL(string: "https://flechemoica.fr/mentions-legales.html")
    private let privacyURL = URL(string: "https://flechemoica.fr/privacy.html")

    @State private var presentedPage: SettingsLegalPage?

    var body: some View {
        VStack(spacing: 4) {
            Text("© 2026 Flèche-moi ça")

            HStack(spacing: 14) {
                if let legalNoticeURL {
                    Button {
                        presentedPage = SettingsLegalPage(title: "Mentions légales", url: legalNoticeURL)
                    } label: {
                        Text("Mentions légales")
                            .font(.xpTahoma(size: 13))
                    }
                    .buttonStyle(.plain)
                }

                if let privacyURL {
                    Button {
                        presentedPage = SettingsLegalPage(title: "Confidentialité", url: privacyURL)
                    } label: {
                        Text("Confidentialité")
                            .font(.xpTahoma(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.xpTahoma(size: 13))
        .foregroundStyle(Color.black.opacity(0.62))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.xpChrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(red: 0.79, green: 0.77, blue: 0.69)).frame(height: 1)
        }
        .sheet(item: $presentedPage) { page in
            SettingsInternalWebSheet(page: page)
        }
    }
}

private struct SettingsLegalPage: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct SettingsInternalWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    let page: SettingsLegalPage

    var body: some View {
        NavigationView {
            SettingsWebView(url: page.url)
                .navigationTitle(page.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct SettingsWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct EditorBadge: View {
    var body: some View {
        Text("Éditeur")
            .font(.xpTahoma(size: 12, weight: .bold))
            .foregroundStyle(.black.opacity(0.78))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(red: 0.78, green: 0.78, blue: 0.78))
            .overlay(Rectangle().stroke(Color.black.opacity(0.45), lineWidth: 1))
    }
}

private struct AvatarBadge: View {
    let name: String
    var size: CGFloat = 78

    var body: some View {
        ZStack {
            Color.white

            if let image = UIImage(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Text(name)
                    .font(.xpTahoma(size: 18, weight: .bold))
                    .foregroundStyle(.black.opacity(0.65))
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 1))
    }
}

private extension View {
    func xpPanelCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Color.xpPanel)
            .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
    }

    func settingsPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .xpPanelCard()
    }

    func profileInputStyle() -> some View {
        self
            .font(.custom("Tahoma", size: 16))
            .foregroundStyle(.black)
            .tint(.black)
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color(red: 0.44, green: 0.55, blue: 0.66), lineWidth: 2))
    }
}
