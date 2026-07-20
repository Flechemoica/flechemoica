import AuthenticationServices
import AppTrackingTransparency
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
    @State private var hasRecordedAppLaunch = false
    @State private var homeCommunicationConfig = HomeCommunicationConfig()
    @State private var homeCommunications: [HomeCommunication] = []
    @State private var answeredPollCommunicationIDs: Set<String> = []
    @State private var homeCommunicationConfigListener: ListenerRegistration?
    @State private var homeCommunicationsListener: ListenerRegistration?
    @State private var adPlacementConfig = AdPlacementConfig()
    @State private var adPlacementConfigListener: ListenerRegistration?

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

    private var activeHomeCommunications: [HomeCommunication] {
        let now = Date()
        let visibleCommunications = homeCommunications.filter {
            !$0.isTestMode || isEditor
        }

        if isEditor, let activeTestCommunication = visibleCommunications.first(where: {
            $0.isTestMode && homeCommunicationConfig.activeCommunicationIDs.contains($0.id)
        }) {
            return [activeTestCommunication]
        }

        if let reservedAdvertisement = visibleCommunications.first(where: {
            $0.type == .sponsored && $0.isScheduledActive(at: now)
        }) {
            return [reservedAdvertisement]
        }

        guard let activeCommunicationID = homeCommunicationConfig.activeCommunicationID else {
            return [.admobCommunication]
        }

        if activeCommunicationID == HomeCommunication.admobCommunicationID {
            return [.admobCommunication]
        }

        if let communication = visibleCommunications.first(where: { $0.id == activeCommunicationID }) {
            guard !communication.hasSchedule || communication.isScheduledActive(at: now) else {
                return [.admobCommunication]
            }

            // Un sondage reste affiché après le vote au lieu d'être remplacé par AdMob.
            return [communication]
        }

        if let scheduledCommunication = visibleCommunications.first(where: {
            $0.isScheduledActive(at: now)
        }) {
            return [scheduledCommunication]
        }

        return [.admobCommunication]
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
                            userID: user.uid,
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
                            selectedGridIsUpcoming: selectedGridIsUpcoming,
                            selectedGridIsCurrent: selectedGridIsCurrent,
                            communicationConfig: homeCommunicationConfig,
                            activeCommunications: activeHomeCommunications,
                            adPlacementConfig: adPlacementConfig,
                            pollVoteAction: voteInPoll,
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
            // Un changement de compte ne doit jamais conserver les droits editor
            // du compte précédent pendant le chargement du nouveau profil.
            isEditor = false
            await refreshAuthenticatedProfile()
            await loadPublishedGrids()
            openPendingNotificationGridIfNeeded()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !isDeletingAccount else { return }
            await refreshAuthenticatedProfile()
            await loadPublishedGrids()
            openPendingNotificationGridIfNeeded()
        }
        .onAppear {
            startHomeCommunicationListeners()
        }
        .onDisappear {
            stopHomeCommunicationListeners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weeklyGridNotificationSelected)) { notification in
            guard let gridID = notification.userInfo?["gridID"] as? String, !gridID.isEmpty else {
                return
            }

            PushNotificationManager.shared.clearPendingWeeklyGridID(gridID)
            openGridFromNotification(gridID: gridID)
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
            await recordAppLaunchIfNeeded(document: document)
        } catch {
            // En cas d'échec réseau ou Firestore, le comportement sûr consiste à
            // masquer les communications réservées aux comptes editor.
            isEditor = false
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

    private func recordAppLaunchIfNeeded(document: DocumentReference) async {
        guard !isDeletingAccount, !hasRecordedAppLaunch else { return }
        hasRecordedAppLaunch = true

        do {
            try await document.setData([
                "lastAppLaunchAt": FieldValue.serverTimestamp()
            ], merge: true)
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
        guard let selectedPublishedGrid, !selectedPublishedGrid.isUpcoming else {
            return false
        }

        guard adPlacementConfig.isEnabled("rewardedGrid") else {
            return false
        }

        return !selectedGridIsCurrent
            && !isGridCompleted(selectedPublishedGrid)
            && !rewardUnlockedGridIDs.contains(selectedPublishedGrid.id)
    }

    private var selectedGridIsCompleted: Bool {
        guard let selectedPublishedGrid, !selectedPublishedGrid.isUpcoming else { return false }
        return isGridCompleted(selectedPublishedGrid)
    }

    private var selectedGridIsUpcoming: Bool {
        selectedPublishedGrid?.isUpcoming ?? false
    }

    private var selectedGridIsCurrent: Bool {
        guard let selectedPublishedGrid, !selectedPublishedGrid.isUpcoming else {
            return false
        }

        let availableGrids = publishedGrids.filter { !$0.isUpcoming }

        guard let currentGrid = availableGrids.max(by: {
            $0.releaseAt < $1.releaseAt
        }) else {
            return false
        }

        return selectedPublishedGrid.id == currentGrid.id
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

    @MainActor
    private func loadPublishedGrids() async {
        isLoadingPublishedGrids = true
        gridLoadingMessage = nil

        let previouslySelectedGridID = selectedPublishedGrid?.id

        do {
            let database = Firestore.firestore()

            let snapshot = try await database
                .collection("grids")
                .whereField("type", isEqualTo: "WeeklyGrid")
                .whereField("status", isEqualTo: "published")
                .limit(to: 50)
                .getDocuments()

            let allGrids = snapshot.documents
                .compactMap(PublishedGrid.init(document:))

            let nextUpcomingGrid = allGrids
                .filter { $0.isUpcoming }
                .min { $0.releaseAt < $1.releaseAt }

            let availableGrids = allGrids
                .filter { !$0.isUpcoming }
                .sorted { $0.releaseAt > $1.releaseAt }

            publishedGrids = []

            if let nextUpcomingGrid {
                publishedGrids.append(nextUpcomingGrid)
            }

            publishedGrids.append(contentsOf: availableGrids)

            if let previouslySelectedGridID,
               let preservedIndex = publishedGrids.firstIndex(where: {
                   $0.id == previouslySelectedGridID
               }) {
                selectedGridIndex = preservedIndex
            } else {
                selectedGridIndex = defaultSelectedGridIndex(in: publishedGrids)
            }

            gridLoadingMessage = publishedGrids.isEmpty
                ? "Aucune grille publiee"
                : nil

            await loadCompletedPlayerCounts()
        } catch {
            let nsError = error as NSError
            gridLoadingMessage = "Erreur de chargement: \(nsError.localizedDescription)"
        }

        isLoadingPublishedGrids = false
    }

    private func defaultSelectedGridIndex(in grids: [PublishedGrid]) -> Int {
        grids.firstIndex(where: { !$0.isUpcoming }) ?? 0
    }

    private func startHomeCommunicationListeners() {
        let database = Firestore.firestore()

        if homeCommunicationConfigListener == nil {
            homeCommunicationConfigListener = database
                .collection("appConfiguration")
                .document("homeCommunication")
                .addSnapshotListener { snapshot, error in
                    Task { @MainActor in
                        if let error {
                            print("Home communication config listener failed: \(error.localizedDescription)")
                            return
                        }

                        homeCommunicationConfig = HomeCommunicationConfig(snapshot: snapshot)
                        await refreshAnsweredActivePoll()
                    }
                }
        }

        if homeCommunicationsListener == nil {
            homeCommunicationsListener = database
                .collection("homeCommunications")
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .addSnapshotListener { snapshot, error in
                    Task { @MainActor in
                        if let error {
                            print("Home communications listener failed: \(error.localizedDescription)")
                            return
                        }

                        homeCommunications = snapshot?.documents.compactMap(HomeCommunication.init(document:)) ?? []
                        await refreshAnsweredActivePoll()
                    }
                }
        }

        if adPlacementConfigListener == nil {
            adPlacementConfigListener = database
                .collection("appConfiguration")
                .document("adPlacements")
                .addSnapshotListener { snapshot, error in
                    Task { @MainActor in
                        if let error {
                            print("Ad placement config listener failed: \(error.localizedDescription)")
                            return
                        }

                        adPlacementConfig = AdPlacementConfig(snapshot: snapshot)
                    }
                }
        }
    }

    private func stopHomeCommunicationListeners() {
        homeCommunicationConfigListener?.remove()
        homeCommunicationsListener?.remove()
        adPlacementConfigListener?.remove()
        homeCommunicationConfigListener = nil
        homeCommunicationsListener = nil
        adPlacementConfigListener = nil
    }

    private func refreshAnsweredActivePoll() async {
        guard let communication = activeHomeCommunications.first,
              communication.type == .poll else {
            return
        }

        if answeredPollCommunicationIDs.contains(communication.id) {
            return
        }

        do {
            let vote = try await Firestore.firestore()
                .collection("homeCommunications")
                .document(communication.id)
                .collection("votes")
                .document(user.uid)
                .getDocument()

            if vote.exists {
                answeredPollCommunicationIDs.insert(communication.id)
            }
        } catch {
            print("Poll vote state load failed: \(error.localizedDescription)")
        }
    }

    private func voteInPoll(_ communication: HomeCommunication, option: String) {
        let selectedOption = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard communication.type == .poll, !selectedOption.isEmpty else { return }

        answeredPollCommunicationIDs.insert(communication.id)

        Firestore.firestore()
            .collection("homeCommunications")
            .document(communication.id)
            .collection("votes")
            .document(user.uid)
            .setData([
                "communicationID": communication.id,
                "userID": user.uid,
                "option": selectedOption,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                if let error {
                    Task { @MainActor in
                        answeredPollCommunicationIDs.remove(communication.id)
                        print("Poll vote failed: \(error.localizedDescription)")
                    }
                }
            }
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
        guard let selectedPublishedGrid else {
            return
        }

        gridAccessMessage = nil

        guard !selectedPublishedGrid.isUpcoming else {
            gridAccessMessage = "Cette grille sera disponible le \(selectedPublishedGrid.formattedReleaseDate)."
            return
        }

        guard !selectedGridIsCurrent,
              !isGridCompleted(selectedPublishedGrid),
              !rewardUnlockedGridIDs.contains(selectedPublishedGrid.id) else {
            openGrid(selectedPublishedGrid)
            return
        }

        guard adPlacementConfig.isEnabled("rewardedGrid") else {
            openGrid(selectedPublishedGrid)
            return
        }

        Task {
            await rewardedGridAccessAd.showAd(
                adUnitID: "ca-app-pub-1003964550278910/8860825770",
                userID: user.uid,
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

    @MainActor
    private func openGrid(_ grid: PublishedGrid) {
        guard !grid.isUpcoming else {
            gridAccessMessage = "Cette grille sera disponible le \(grid.formattedReleaseDate)."
            selectedGameGrid = nil
            return
        }

        guard grid.isPlayable else {
            gridAccessMessage = "Cette grille est indisponible."
            selectedGameGrid = nil
            return
        }

        if completedGridTitles.contains(grid.title) {
            UserDefaults.standard.set(true, forKey: userScopedGridStorageKey(prefix: "gridCompleted", gridID: grid.id))
        }

        selectedGameGrid = publishedGrids.first { $0.id == grid.id } ?? grid
    }

    @MainActor
    private func openPendingNotificationGridIfNeeded() {
        guard let gridID = PushNotificationManager.shared.consumePendingWeeklyGridID(), !gridID.isEmpty else {
            return
        }

        openGridFromNotification(gridID: gridID)
    }

    @MainActor
    private func openGridFromNotification(gridID: String) {
        Task { @MainActor in
            await openGridFromNotificationAsync(gridID: gridID)
        }
    }

    @MainActor
    private func openGridFromNotificationAsync(gridID: String) async {
        if publishedGrids.isEmpty {
            await loadPublishedGrids()
        }

        if let grid = publishedGrids.first(where: { $0.id == gridID }) {
            openGrid(grid)
            return
        }

        do {
            let database = Firestore.firestore()
            let snapshot = try await database.collection("grids").document(gridID).getDocument()
            if let grid = PublishedGrid(snapshot: snapshot) {
                guard grid.isPlayable else {
                    gridAccessMessage = "Cette grille est indisponible."
                    return
                }

                if !publishedGrids.contains(where: { $0.id == grid.id }) {
                    publishedGrids.insert(grid, at: 0)
                }
                selectedGridIndex = publishedGrids.firstIndex(where: { $0.id == grid.id }) ?? 0
                selectedGameGrid = grid
            } else {
                gridAccessMessage = "Cette grille est introuvable."
            }
        } catch {
            gridAccessMessage = "Impossible d'ouvrir cette grille."
        }
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
    private var statsUserID: String?

    private var effectiveAdUnitID: String {
        AdMobConfiguration.rewardedAdUnitID(productionID: productionAdUnitID ?? "")
    }

    private var productionAdUnitID: String?
    #endif

    func showAd(
        adUnitID: String,
        userID: String,
        customData: String,
        rewarded: @escaping (Bool) -> Void
    ) async {
        #if canImport(GoogleMobileAds)
        productionAdUnitID = adUnitID
        statsUserID = userID
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
    private func loadAd(customData: String, retryCount: Int = 2) async throws -> RewardedAd {
        isLoading = true
        defer { isLoading = false }

        await AdMobConfiguration.refreshTestAdsStatus()

        do {
            let ad = try await RewardedAd.load(with: effectiveAdUnitID, request: Request())
            let options = ServerSideVerificationOptions()
            options.customRewardText = customData
            ad.serverSideVerificationOptions = options
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            return ad
        } catch {
            guard retryCount > 0 else { throw error }
            try await Task.sleep(nanoseconds: 800_000_000)
            return try await loadAd(customData: customData, retryCount: retryCount - 1)
        }
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
    nonisolated func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            AdStatsRecorder.record(userID: statsUserID, placement: "rewarded", event: "impression")
        }
    }

    nonisolated func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            AdStatsRecorder.record(userID: statsUserID, placement: "rewarded", event: "click")
        }
    }

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
        self.init(id: document.documentID, data: document.data())
    }

    init?(snapshot: DocumentSnapshot) {
        guard snapshot.exists, let data = snapshot.data() else {
            return nil
        }

        self.init(id: snapshot.documentID, data: data)
    }

    private init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String,
              let releaseTimestamp = data["releaseAt"] as? Timestamp else {
            return nil
        }
        guard data["type"] as? String == "WeeklyGrid" else {
            return nil
        }

        self.id = id
        self.title = title
        self.releaseAt = releaseTimestamp.dateValue()
        self.completedPlayerCount = data["completedPlayerCount"] as? Int ?? 0
        self.crosswordGrid = CrosswordGrid(firestoreData: data, fallbackTitle: title)
    }

    var formattedReleaseDate: String {
        Self.releaseDateFormatter.string(from: releaseAt)
    }

    var isUpcoming: Bool {
        releaseAt > Date()
    }

    var isPlayable: Bool {
        guard !isUpcoming, let crosswordGrid else { return false }
        return !crosswordGrid.placedWords.isEmpty && !crosswordGrid.solutionLetters.isEmpty
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
                    // Les définitions horizontales sont affichées avant les verticales
                    if lhs.isVertical != rhs.isVertical {
                        return !lhs.isVertical
                    }

                    return lhs.definitionSlotPriority < rhs.definitionSlotPriority
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
    
    var isVertical: Bool {

        direction.rowDelta == 1 && direction.columnDelta == 0

    }

    var arrowSymbol: String {
        direction.rowDelta == 1 ? "↓" : "→"
    }

    var arrowStyle: DefinitionArrowStyle {
        if direction.rowDelta == 1 && direction.columnDelta == 0 {
            return direction.startColumnDelta == 1 ? .cornerDownRight : .down
        }

        if direction.rowDelta == 0 && direction.columnDelta == 1 {
            return direction.startRowDelta == 1 ? .cornerRightDown : .right
        }

        return .right
    }

    var definitionSlotPriority: Int {
        arrowStyle.sortPriority
    }
}

private enum DefinitionArrowStyle {
    case right
    case down
    case cornerDownRight
    case cornerRightDown

    var sortPriority: Int {
        switch self {
        case .cornerDownRight:
            return 0
        case .down:
            return 1
        case .right:
            return 2
        case .cornerRightDown:
            return 3
        }
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

private struct HomeCommunicationConfig {
    var isEnabled = true
    var activeCommunicationIDs: Set<String> = []
    var activeCommunicationID: String?
    var blockHeightPX = 500
    var communicationPositions: [String: Int] = [:]

    init() {}

    init(snapshot: DocumentSnapshot?) {
        guard let data = snapshot?.data() else { return }
        let activeIDs = data["activeCommunicationIDs"] as? [String] ?? []
        isEnabled = data["isEnabled"] as? Bool ?? true
        activeCommunicationIDs = Set(activeIDs)
        activeCommunicationID = activeIDs.first
        blockHeightPX = Self.normalizedBlockHeight(data["blockHeightPX"])
        communicationPositions = (data["communicationPositions"] as? [String: Any] ?? [:]).reduce(into: [:]) {
            $0[$1.key] = min(3, max(1, ($1.value as? NSNumber)?.intValue ?? 2))
        }
    }

    var blockHeightPoints: CGFloat {
        CGFloat(blockHeightPX) / UIScreen.main.scale
    }

    private static func normalizedBlockHeight(_ value: Any?) -> Int {
        let rawHeight: Int
        if let value = value as? Int {
            rawHeight = value
        } else if let value = value as? Double {
            rawHeight = Int(value.rounded())
        } else if let value = value as? NSNumber {
            rawHeight = value.intValue
        } else {
            rawHeight = 500
        }

        return min(1100, max(120, rawHeight))
    }
}

private struct AdPlacementConfig {
    var placements: [String: AdPlacementRule] = [:]

    init() {}

    init(snapshot: DocumentSnapshot?) {
        guard let data = snapshot?.data(),
              let rawPlacements = data["placements"] as? [String: [String: Any]] else {
            return
        }

        placements = rawPlacements.mapValues(AdPlacementRule.init(data:))
    }

    func isEnabled(_ placementID: String, at date: Date = Date()) -> Bool {
        guard let placement = placements[placementID] else {
            return true
        }

        return placement.isEnabled(at: date)
    }
}

private struct AdPlacementRule {
    var isEnabled = true
    var startsAt: Date?
    var endsAt: Date?

    nonisolated init(data: [String: Any]) {
        isEnabled = data["isEnabled"] as? Bool ?? true
        startsAt = (data["startsAt"] as? Timestamp)?.dateValue()
        endsAt = (data["endsAt"] as? Timestamp)?.dateValue()
    }

    func isEnabled(at date: Date) -> Bool {
        guard isEnabled else { return false }

        if let startsAt, date < startsAt {
            return false
        }

        if let endsAt, date > endsAt {
            return false
        }

        return true
    }
}

private struct HomeCommunication: Identifiable {
    static let admobCommunicationID = "admobCommunication"

    static let admobCommunication = HomeCommunication(
        id: admobCommunicationID,
        type: .ad,
        text: "Publicité AdMob",
        imageOverlayText: "",
        pollOptions: [],
        imageURL: nil,
        imageDataBase64: nil,
        storagePath: nil,
        clientName: "",
        destinationURL: nil,
        isTestMode: false,
        imageWidth: nil,
        imageHeight: nil,
        mediaKind: "image",
        displayPeriods: [],
        position: 2,
        startsAt: nil,
        endsAt: nil,
        createdAt: .distantFuture
    )

    enum CommunicationType: String {
        case text
        case image
        case poll
        case ad
        case sponsored
    }

    let id: String
    let type: CommunicationType
    let text: String
    let imageOverlayText: String
    let pollOptions: [String]
    let imageURL: String?
    let imageDataBase64: String?
    let storagePath: String?
    let clientName: String
    let destinationURL: URL?
    let isTestMode: Bool
    let imageWidth: CGFloat?
    let imageHeight: CGFloat?
    let mediaKind: String
    let displayPeriods: [DisplayPeriod]
    let position: Int
    let startsAt: Date?
    let endsAt: Date?
    let createdAt: Date

    private init(
        id: String,
        type: CommunicationType,
        text: String,
        imageOverlayText: String,
        pollOptions: [String],
        imageURL: String?,
        imageDataBase64: String?,
        storagePath: String?,
        clientName: String,
        destinationURL: URL?,
        isTestMode: Bool,
        imageWidth: CGFloat?,
        imageHeight: CGFloat?,
        mediaKind: String,
        displayPeriods: [DisplayPeriod],
        position: Int,
        startsAt: Date?,
        endsAt: Date?,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.imageOverlayText = imageOverlayText
        self.pollOptions = pollOptions
        self.imageURL = imageURL
        self.imageDataBase64 = imageDataBase64
        self.storagePath = storagePath
        self.clientName = clientName
        self.destinationURL = destinationURL
        self.isTestMode = isTestMode
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.mediaKind = mediaKind
        self.displayPeriods = displayPeriods
        self.position = position
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.createdAt = createdAt
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        let text = data["text"] as? String ?? ""
        let imageOverlayText = data["imageOverlayText"] as? String ?? ""
        let rawType = data["type"] as? String ?? ""
        let storedType = CommunicationType(rawValue: rawType)
        let pollOptions = data["pollOptions"] as? [String] ?? []
        let imageURL = data["imageURL"] as? String
        let imageDataBase64 = data["imageDataBase64"] as? String
        let storagePath = data["storagePath"] as? String
        let clientName = data["clientName"] as? String ?? ""
        let destinationURL = (data["destinationURL"] as? String).flatMap(URL.init(string:))
        let isTestMode = data["isTestMode"] as? Bool ?? false
        let imageWidth = (data["imageWidth"] as? NSNumber).map { CGFloat($0.doubleValue) }
        let imageHeight = (data["imageHeight"] as? NSNumber).map { CGFloat($0.doubleValue) }
        let mediaKind = data["mediaKind"] as? String ?? "image"
        let displayPeriods = (data["displayPeriods"] as? [[String: Any]] ?? [])
            .compactMap(DisplayPeriod.init(data:))
        let position = min(3, max(1, (data["position"] as? NSNumber)?.intValue ?? 2))
        let startsAt = (data["startsAt"] as? Timestamp)?.dateValue()
        let endsAt = (data["endsAt"] as? Timestamp)?.dateValue()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || imageURL?.isEmpty == false
                || imageDataBase64?.isEmpty == false
                || storedType == .ad
                || storedType == .sponsored
                || (storedType == .poll && pollOptions.count >= 2) else {
            return nil
        }

        id = document.documentID
        type = storedType ?? (imageURL?.isEmpty == false || imageDataBase64?.isEmpty == false ? .image : .text)
        self.text = text
        self.imageOverlayText = imageOverlayText
        self.pollOptions = pollOptions
        self.imageURL = imageURL
        self.imageDataBase64 = imageDataBase64
        self.storagePath = storagePath
        self.clientName = clientName
        self.destinationURL = destinationURL
        self.isTestMode = isTestMode
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.mediaKind = mediaKind
        self.displayPeriods = displayPeriods
        self.position = position
        self.startsAt = startsAt
        self.endsAt = endsAt
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
    }

    var hasSchedule: Bool {
        !displayPeriods.isEmpty || startsAt != nil || endsAt != nil
    }

    func isScheduledActive(at date: Date) -> Bool {
        guard hasSchedule else { return false }

        if !displayPeriods.isEmpty {
            return displayPeriods.contains { $0.contains(date) }
        }

        if let startsAt, date < startsAt {
            return false
        }

        if let endsAt, date > endsAt {
            return false
        }

        return true
    }

    var imageAspectRatio: CGFloat? {
        guard let imageWidth, let imageHeight, imageWidth > 0, imageHeight > 0 else { return nil }
        return imageWidth / imageHeight
    }

    var hasImage: Bool {
        imageURL?.isEmpty == false || imageDataBase64?.isEmpty == false || storagePath?.isEmpty == false
    }

    var image: UIImage? {
        guard let imageDataBase64,
              let data = Data(base64Encoded: imageDataBase64) else {
            return nil
        }

        return UIImage(data: data)
    }
}

private struct DisplayPeriod {
    let startsAt: Date
    let endsAt: Date

    nonisolated init?(data: [String: Any]) {
        guard let startsAt = (data["startsAt"] as? Timestamp)?.dateValue(),
              let endsAt = (data["endsAt"] as? Timestamp)?.dateValue(),
              startsAt < endsAt else { return nil }
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    func contains(_ date: Date) -> Bool {
        startsAt <= date && date < endsAt
    }
}

private enum SponsoredAdStatsRecorder {
    static func record(communicationID: String, userID: String, isEditor: Bool, event: String) {
        guard !isEditor else { return }
        guard event == "impression" || event == "click" else { return }

        var data: [String: Any] = [
            "communicationID": communicationID,
            "event": event
        ]
        if ATTrackingManager.trackingAuthorizationStatus == .authorized {
            let digest = SHA256.hash(data: Data("\(communicationID):\(userID)".utf8))
            data["visitorID"] = digest.map { String(format: "%02x", $0) }.joined()
            data["trackingConsent"] = "attAuthorized"
        }

        Task {
            guard let currentUser = Auth.auth().currentUser,
                  let endpoint = URL(string: "https://europe-west1-flechemoica.cloudfunctions.net/recordSponsoredAdEvent") else { return }
            do {
                let token = try await currentUser.getIDToken()
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])
                _ = try await URLSession.shared.data(for: request)
            } catch {
                return
            }
        }
    }
}

private struct HomeContent: View {
    let userID: String
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
    let selectedGridIsUpcoming: Bool
    let selectedGridIsCurrent: Bool
    let communicationConfig: HomeCommunicationConfig
    let activeCommunications: [HomeCommunication]
    let adPlacementConfig: AdPlacementConfig
    let pollVoteAction: (HomeCommunication, String) -> Void
    let profileAction: () -> Void
    let previousGridAction: () -> Void
    let nextGridAction: () -> Void
    let playGridAction: () -> Void
    let wizzAction: () -> Void

    @State private var contentWidth: CGFloat = UIScreen.main.bounds.width - 34

    private var adBlockHeight: CGFloat {
        (contentWidth / (16 / 9)) + 78
    }

    private var sponsoredBlockHeight: CGFloat {
        let ratio = activeCommunications.first(where: { $0.type == .sponsored })?.imageAspectRatio ?? (16 / 9)
        return contentWidth / ratio
    }

    private var activeCommunicationPosition: Int {
        guard let communication = activeCommunications.first else { return 2 }
        if communication.id == HomeCommunication.admobCommunicationID {
            return communicationConfig.communicationPositions[communication.id] ?? 2
        }
        return communication.position
    }

    var body: some View {
        VStack(spacing: 14) {
            if activeCommunicationPosition == 1 {
                announcementCard
            }

            Button(action: profileAction) {
                ProfileSummaryCard(
                    displayName: displayName,
                    avatarName: avatarName,
                    isEditor: isEditor
                )
            }
            .buttonStyle(.plain)

            if activeCommunicationPosition == 2 {
                announcementCard
            }

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
                isUpcoming: selectedGridIsUpcoming,
                isCurrent: selectedGridIsCurrent,
                previousAction: previousGridAction,
                nextAction: nextGridAction,
                playAction: playGridAction
            )

            if activeCommunicationPosition == 3 {
                announcementCard
            }

            Spacer(minLength: 0)

            WizzFooter(wizzAction: wizzAction)
        }
        .padding(14)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentWidth = proxy.size.width - 28 }
                    .onChange(of: proxy.size.width) { _, width in
                        contentWidth = width - 28
                    }
            }
        }
    }

    @ViewBuilder
    private var announcementCard: some View {
        if communicationConfig.isEnabled && !activeCommunications.isEmpty {
            HomeAnnouncementCard(
                communications: activeCommunications,
                config: communicationConfig,
                adPlacementConfig: adPlacementConfig,
                userID: userID,
                isEditor: isEditor,
                adMediaAspectRatio: 16 / 9,
                adBlockHeight: adBlockHeight,
                sponsoredBlockHeight: sponsoredBlockHeight,
                pollVoteAction: pollVoteAction
            )
        }
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

private struct HomeAnnouncementCard: View {
    let communications: [HomeCommunication]
    let config: HomeCommunicationConfig
    let adPlacementConfig: AdPlacementConfig
    let userID: String
    let isEditor: Bool
    let adMediaAspectRatio: CGFloat
    let adBlockHeight: CGFloat
    let sponsoredBlockHeight: CGFloat
    let pollVoteAction: (HomeCommunication, String) -> Void

    var body: some View {
        Group {
            if !config.isEnabled {
                placeholderView(status: "Bloc desactive")
            } else if communications.isEmpty {
                placeholderView(status: "Aucune communication")
            } else if communications.count == 1, let communication = communications.first {
                HomeCommunicationSlide(
                    communication: communication,
                    adPlacementConfig: adPlacementConfig,
                    userID: userID,
                    isEditor: isEditor,
                    adMediaAspectRatio: adMediaAspectRatio,
                    pollVoteAction: pollVoteAction
                )
            } else {
                TabView {
                    ForEach(communications) { communication in
                        HomeCommunicationSlide(
                            communication: communication,
                            adPlacementConfig: adPlacementConfig,
                            userID: userID,
                            isEditor: isEditor,
                            adMediaAspectRatio: adMediaAspectRatio,
                            pollVoteAction: pollVoteAction
                        )
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: blockHeight)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(
                    Color(red: 0.5, green: 0.62, blue: 0.73),
                    lineWidth: 2
                )
        }
    }

    private var blockHeight: CGFloat {
        if communications.contains(where: { $0.type == .ad }) { return adBlockHeight }
        if communications.contains(where: { $0.type == .sponsored }) { return sponsoredBlockHeight }
        return config.blockHeightPoints
    }

    private func placeholderView(status: String) -> some View {
        GeometryReader { proxy in
            let scale = UIScreen.main.scale
            let width = Int((proxy.size.width * scale).rounded())
            let height = Int((proxy.size.height * scale).rounded())

            ZStack {
                Color.white

                VStack(spacing: 6) {
                    Text(status)
                        .font(.xpTahoma(size: 17, weight: .bold))
                        .foregroundStyle(.black.opacity(0.65))

                    Text("\(width) x \(height) px")
                        .font(.custom("Tahoma", size: 13))
                        .foregroundStyle(.black.opacity(0.58))
                }
            }
        }
    }
}

private struct RemoteAnimatedMediaView: UIViewRepresentable {
    let url: URL
    let isVideo: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let source = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let mediaTag = isVideo
            ? "<video src=\"\(source)\" autoplay muted loop playsinline></video>"
            : "<img src=\"\(source)\" alt=\"\">"
        webView.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}img,video{width:100%;height:100%;object-fit:cover}</style>
        \(mediaTag)
        """, baseURL: nil)
    }
}

private struct HomeCommunicationSlide: View {
    let communication: HomeCommunication
    let adPlacementConfig: AdPlacementConfig
    let userID: String
    let isEditor: Bool
    let adMediaAspectRatio: CGFloat
    let pollVoteAction: (HomeCommunication, String) -> Void
    @State private var didRecordSponsoredImpression = false

    var body: some View {
        Group {
            switch communication.type {
            case .poll:
                pollView
            case .ad:
                adView
            case .sponsored:
                sponsoredView
            case .image, .text:
                imageOrTextView
            }
        }
        .clipped()
    }

    private var sponsoredView: some View {
        Button {
            guard let destinationURL = communication.destinationURL else { return }
            SponsoredAdStatsRecorder.record(
                communicationID: communication.id,
                userID: userID,
                isEditor: isEditor,
                event: "click"
            )
            UIApplication.shared.open(destinationURL)
        } label: {
            ZStack(alignment: .topLeading) {
                Color.white
                communicationImage

                Text("Annonce")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Color(red: 192 / 255, green: 173 / 255, blue: 238 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Annonce de \(communication.clientName)")
        .onAppear {
            guard !didRecordSponsoredImpression else { return }
            didRecordSponsoredImpression = true
            SponsoredAdStatsRecorder.record(
                communicationID: communication.id,
                userID: userID,
                isEditor: isEditor,
                event: "impression"
            )
        }
    }

    private var imageOrTextView: some View {
        ZStack {
            Color.white

            communicationImage

            if communication.type == .image,
               !communication.imageOverlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                imageOverlayText
            } else if !communication.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                communicationText
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(communication.hasImage ? Color.white.opacity(0.78) : Color.clear)
            }
        }
    }

    @ViewBuilder
    private var communicationImage: some View {
        if let image = communication.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let imageURL = communication.imageURL, let url = URL(string: imageURL) {
            if communication.mediaKind == "video" || communication.mediaKind == "gif" {
                RemoteAnimatedMediaView(url: url, isVideo: communication.mediaKind == "video")
            } else {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                } failure: {
                    communicationText
                }
            }
        }
    }

    private var pollView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(communication.text)
                .font(.xpTahoma(size: 17, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            VStack(spacing: 7) {
                ForEach(Array(communication.pollOptions.prefix(4)), id: \.self) { option in
                    Button {
                        pollVoteAction(communication, option)
                    } label: {
                        Text(option)
                            .font(.xpTahoma(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.xpPanel)
    }

    private var adView: some View {
        Group {
            if adPlacementConfig.isEnabled("communicationBlock") {
                HomeNativeAdCard(
                    adUnitID: "ca-app-pub-1003964550278910/6276883284",
                    userID: userID,
                    mediaAspectRatio: adMediaAspectRatio,
                    fillsAvailableSpace: true
                )
            } else {
                Color.white
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.xpPanel)
    }

    private var communicationText: some View {
        Text(communication.text)
            .font(.xpTahoma(size: 17, weight: .bold))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.78)
    }

    private var imageOverlayText: some View {
        GeometryReader { proxy in
            let fontSize = min(52, max(19, proxy.size.height * 0.105))
            let trailingPadding = max(12, proxy.size.width * 0.033)
            let bottomPadding = max(8, proxy.size.height * 0.04)

            Text(communication.imageOverlayText.uppercased())
                .font(.system(size: fontSize, weight: .heavy).italic())
                .foregroundStyle(.black)
                .lineLimit(3)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(.trailing)
                .allowsTightening(true)
                .frame(maxWidth: proxy.size.width * 0.78, maxHeight: .infinity, alignment: .bottomTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, trailingPadding)
                .padding(.bottom, bottomPadding)
        }
        .allowsHitTesting(false)
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
    let isUpcoming: Bool
    let isCurrent: Bool
    let previousAction: () -> Void
    let nextAction: () -> Void
    let playAction: () -> Void

    private var canGoToOlderGrid: Bool {
        selectedIndex + 1 < gridCount
    }

    private var canGoToNewerGrid: Bool {
        selectedIndex > 0
    }

    private var gridStatusTitle: String {
        if isUpcoming {
            return "Grille à venir"
        }

        return isCurrent ? "Grille de la semaine" : "Grille précédente"
    }

    private var playButtonTitle: String {
        if isCompleted {
            return "Revoir"
        }

        if isUpcoming {
            return "A venir"
        }

        if isLoadingRewardedAd {
            return "Chargement..."
        }

        return requiresRewardedAd ? "Jouer après pub" : "Jouer"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(gridStatusTitle)
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

                    Text("📅 \(isUpcoming ? "Disponible le" : "Publiée le") \(grid.formattedReleaseDate)")
                        .font(.custom("Tahoma", size: 13))
                        .foregroundStyle(.black.opacity(0.72))
                        .lineLimit(1)

                    Text("👥 \(grid.completedPlayerCount) \(grid.completedPlayerCount >= 2 ? "joueurs ont" : "joueur a") terminé cette grille")
                    .font(.custom("Tahoma", size: 13))
                    .foregroundStyle(.black.opacity(0.72))
                    .lineLimit(1)
                    .opacity(isUpcoming ? 0 : 1)
                    .accessibilityHidden(isUpcoming)
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

                Button(action: playAction) {
                    Text(playButtonTitle)
                        .font(.xpTahoma(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(XPButtonStyle())
                .frame(maxWidth: .infinity)
                .opacity(grid == nil || isUpcoming || isLoadingRewardedAd ? 0.45 : 1)
                .disabled(grid == nil || isUpcoming || isLoadingRewardedAd)

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
    @State private var isKeyboardVisible = false
    @State private var isShowingGridTutorial = false
    @State private var canVerifyLetters = false
    
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
            let fullBoardHeight = (proxy.size.width - 28)
                * CGFloat(CrosswordGrid.rowCount)
                / CGFloat(CrosswordGrid.columnCount)
            // Le bandeau de définition doit rester visible au-dessus du clavier.
            // Seule la fenêtre qui découpe la grille rétrécit : son contenu garde
            // sa taille et reste ancré en haut.
            let keyboardBoardHeight = max(96, proxy.size.height - 152)
            let boardViewportHeight = isKeyboardVisible
                ? min(fullBoardHeight, keyboardBoardHeight)
                : fullBoardHeight

            VStack(spacing: 10) {
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
                        XPToolbarIconButton(
                            systemName: "arrow.left",
                            accessibilityLabel: "Quitter la grille",
                            action: backAction
                        )
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
                    isReadOnly: isCompleted,
                    isKeyboardVisible: isKeyboardVisible,
                    selectedWordID: $selectedWordID,
                    selectedCell: $selectedCell,
                    inputIndex: $inputIndex
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: boardViewportHeight,
                    maxHeight: boardViewportHeight,
                    alignment: .topLeading
                )
                .layoutPriority(1)

                if isCompleted {
                    Text(completionStatusText)
                        .font(.xpTahoma(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.xpPanel)
                        .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
                } else {
                    HStack(spacing: 8) {
                        if let selectedWord {
                            Text((selectedWord.definitions.first ?? "DÉFINITION").uppercased())
                                .font(.xpTahoma(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.xpPanel)
                                .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
                        } else {
                            Spacer(minLength: 0)
                        }

                        GridToolsBar(
                            canVerify: canVerifyLetters,
                            canRevealLetter: selectedCell != nil,
                            verifyAction: {
                                canVerifyLetters = false

                                if verifyAnswers(), isGridFullyAnswered() {
                                    closeKeyboard()
                                    completeGrid()
                                }
                            },
                            revealLetterAction: revealSelectedLetter
                        )
                        .frame(width: 174)
                    }
                    .frame(height: 36)
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
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
        .overlay {
            if isShowingGridTutorial {
                GridTutorialOverlay {
                    UserDefaults.standard.set(true, forKey: gridTutorialSeenKey)

                    withAnimation(.easeOut(duration: 0.2)) {
                        isShowingGridTutorial = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear {
            loadSavedAnswers()
            loadSavedElapsedSeconds()
            loadCompletionState()

            isShowingGridTutorial =
                !UserDefaults.standard.bool(forKey: gridTutorialSeenKey)

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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardVisible = false
            }
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
    private var gridTutorialSeenKey: String {
        "gridTutorialSeen.\(safeUserStorageKey)"
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
        
        canVerifyLetters = true

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
    
    private func revealSelectedLetter() {
        guard
            !isCompleted,
            let selectedCell,
            let crosswordGrid = grid.crosswordGrid,
            let correctLetter = crosswordGrid.correctLetter(at: selectedCell)
        else {
            return
        }

        answers[selectedCell] = correctLetter
        wrongCells.remove(selectedCell)
        canVerifyLetters = true

        self.selectedCell = nil
        inputIndex = 0

        checkForCompletedGrid()
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


private struct TutorialBackArrowButton: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.xpPanel)

            Image(systemName: "arrow.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(width: 38, height: 38)
        .overlay(
            Rectangle()
                .stroke(
                    Color(red: 0.5, green: 0.62, blue: 0.73),
                    lineWidth: 2
                )
        )
    }
}



private struct GridTutorialOverlay: View {
    let dismissAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.82)
                    .ignoresSafeArea()

                VStack(spacing: 0) {

                    // Bouton retour en haut à droite
                    HStack {
                        Spacer()

                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Retour à l’écran")
                                Text("d’accueil")
                            }
                            .font(.xpTahoma(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)

                            TutorialBackArrowButton()
                        }
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 16)

                    Spacer(minLength: 30)

                    // Explication des deux types de sélection
                    VStack(spacing: 24) {
                        HStack(spacing: 14) {
                            
                            TutorialDefinitionCell()
                                .frame(width: 64, height: 64)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Sélectionner\nle mot entier")
                                .font(.xpTahoma(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                        }

                        HStack(spacing: 14) {
                            TutorialLetterCell()
                                .frame(width: 64, height: 64)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Sélectionner\nla case seule")
                                .font(.xpTahoma(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Explication des boutons du bas
                    HStack(alignment: .bottom, spacing: 8) {
                        TutorialBottomAction(
                            icon: "list.bullet",
                            text: "Afficher\nl’index"
                        )

                        TutorialBottomAction(
                            icon: "checkmark",
                            text: "Vérifier les\nlettres présentes"
                        )

                        TutorialBottomAction(
                            letter: "A",
                            text: "Révéler la lettre\nsélectionnée"
                        )
                    }
                    .padding(.horizontal, 10)

                    Text("Touchez l’écran pour commencer")
                        .font(.xpTahoma(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.top, 22)
                        .padding(.bottom, 16)
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissAction()
            }
        }
    }
}

private struct TutorialDefinitionCell: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    Color(
                        red: 193 / 255,
                        green: 174 / 255,
                        blue: 238 / 255
                    )
                )

            Text("CAPITALE\nDE L’ITALIE")
                .font(.xpTahoma(size: 7, weight: .bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(3)


        }
        .overlay(
            Rectangle()
                .stroke(.white, lineWidth: 4)
        )
        .shadow(color: .white.opacity(0.8), radius: 10)
    }
}

private struct TutorialLetterCell: View {
    var body: some View {
        Rectangle()
            .fill(Color.white)
            .overlay(
                Rectangle()
                    .stroke(.white, lineWidth: 4)
            )
            .shadow(color: .white.opacity(0.8), radius: 10)
    }
}

private struct TutorialBottomAction: View {
    var icon: String?
    var letter: String?
    let text: String

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Rectangle()
                    .fill(Color.xpPanel)

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                }

                if let letter {
                    Text(letter)
                        .font(.xpTahoma(size: 19, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 50, height: 38)
            .overlay(
                Rectangle()
                    .stroke(
                        Color(red: 0.5, green: 0.62, blue: 0.73),
                        lineWidth: 2
                    )
            )

            Image(systemName: "arrow.down")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text(text)
                .font(.xpTahoma(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

    private struct GridToolsBar: View {
        let canVerify: Bool
        let canRevealLetter: Bool
    let verifyAction: () -> Void
    let revealLetterAction: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            GridToolButton(
                title: "Index",
                systemImage: "list.bullet",
                letter: nil,
                action: {},
                isEnabled: false
            )

            GridToolButton(
                title: "Vérifier",
                systemImage: "checkmark",
                letter: nil,
                action: verifyAction,
                isEnabled: canVerify
            )

            GridToolButton(
                title: "Révéler",
                systemImage: nil,
                letter: "A",
                action: revealLetterAction,
                isEnabled: canRevealLetter
            )
        }
    }
}

private struct GridToolButton: View {
    let title: String?
    let systemImage: String?
    let letter: String?
    let action: () -> Void
    var isEnabled = true

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .bold))
                }

                if let letter {
                    Text(letter)
                        .font(.xpTahoma(size: 14, weight: .bold))
                }

                if let title {
                    Text(title)
                        .font(.xpTahoma(size: 8.5, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(.black.opacity(isEnabled ? 0.78 : 0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.xpPanel)
        .overlay(
            Rectangle()
                .stroke(
                    Color(red: 0.5, green: 0.62, blue: 0.73)
                        .opacity(isEnabled ? 1 : 0.5),
                    lineWidth: 2
                )
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct CrosswordBoardViewport: View {
    let grid: CrosswordGrid
    @Binding var answers: [GridCoordinate: String]
    let wrongCells: Set<GridCoordinate>
    let isReadOnly: Bool
    let isKeyboardVisible: Bool
    @Binding var selectedWordID: String?
    @Binding var selectedCell: GridCoordinate?
    @Binding var inputIndex: Int

    private let cellSize: CGFloat = 38
    private var rowToCenter: Int? {
        guard isKeyboardVisible else { return nil }

        if let selectedWordID,
           let word = grid.word(id: selectedWordID) {

            let rows = word.letterCoordinates.map(\.row)

            guard let firstRow = rows.min(),
                  let lastRow = rows.max() else {
                return selectedCell?.row
            }

            let isVertical = word.direction.rowDelta != 0

            if isVertical {
                let wordHeight = lastRow - firstRow + 1

                // Le clavier permet d'afficher environ 9 lignes.
                // Si le mot tient dedans, on centre le milieu du mot.
                if wordHeight <= 9 {
                    return (firstRow + lastRow) / 2
                }

                // Pour un mot de plus de 9 lettres, on centre plutôt
                // la case actuellement sélectionnée.
                return selectedCell?.row ?? ((firstRow + lastRow) / 2)
            }

            // Pour un mot horizontal, toutes les lettres sont sur la même ligne.
            return firstRow
        }

        // Clic sur une case qui n'appartient pas à un mot sélectionné.
        return selectedCell?.row
    }
    var body: some View {
        GeometryReader { proxy in
            let boardWidth = CGFloat(CrosswordGrid.columnCount) * cellSize
            let boardHeight = CGFloat(CrosswordGrid.rowCount) * cellSize
            let scale = proxy.size.width / boardWidth

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
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
                            width: boardWidth,
                            height: boardHeight
                        )
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(
                            width: boardWidth * scale,
                            height: boardHeight * scale,
                            alignment: .topLeading
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(Rectangle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                .onChange(of: rowToCenter) { _, newRow in
                    guard let newRow else { return }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(260))

                        withAnimation(.easeOut(duration: 0.22)) {
                            scrollProxy.scrollTo(newRow, anchor: .center)
                        }
                    }
                }
                .onChange(of: isKeyboardVisible) { _, visible in
                    guard visible, let rowToCenter else { return }

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(260))

                        withAnimation(.easeOut(duration: 0.22)) {
                            scrollProxy.scrollTo(rowToCenter, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color.xpPanel)
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(
                    Color(red: 0.5, green: 0.62, blue: 0.73),
                    lineWidth: 2
                )
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
                .id(row)
                .zIndex(Double(CrosswordGrid.rowCount - row))
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
                            segmentCount: definitionWords.count,
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
        .zIndex(isDefinition ? 2 : 0)
        .overlay(Rectangle().stroke(Color.black.opacity(0.72), lineWidth: 0.8))
    }

    private var backgroundColor: Color {
        if isBlack {
            return .black
        }

        if isDefinition {
            return Color(red: 193 / 255, green: 174 / 255, blue: 238 / 255)
        }

        if isWrong {
            return Color(red: 1.0, green: 0.55, blue: 0.52)
        }

        return isSelected ? Color(red: 0.73, green: 0.95, blue: 0.74) : .white
    }
}

private struct DefinitionCellSegment: View {
    let word: CrosswordWord
    let segmentCount: Int
    let isSelected: Bool
    let isReadOnly: Bool
    let action: () -> Void

    private var definitionText: String {
        let text = word.definitions.joined(separator: " / ").uppercased()
        return text.isEmpty ? " " : text
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(definitionText)
                    .font(.xpTahoma(size: segmentCount > 1 ? 5.5 : 6.4, weight: .bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(segmentCount > 1 ? 3 : 4)
                    .minimumScaleFactor(0.42)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)

                DefinitionArrowView(style: word.arrowStyle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color(red: 0.73, green: 0.95, blue: 0.74).opacity(0.72) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .overlay(Rectangle().stroke(Color.black.opacity(isSelected ? 0.55 : 0.18), lineWidth: isSelected ? 1 : 0.5))
    }
}

private struct DefinitionArrowView: View {
    let style: DefinitionArrowStyle

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            let arrowSize = width * 0.14
            let lineWidth: CGFloat = 1.1

            ZStack {

                // ===== Traits =====

                Path { path in
                    switch style {

                    case .right:
                        let y = height * 0.5
                        let startX = width
                        let tipX = width + arrowSize * 1.6

                        path.move(to: CGPoint(x: startX, y: y))
                        path.addLine(to: CGPoint(x: tipX - arrowSize, y: y))

                    case .down:
                        let x = width * 0.5
                        let startY = height
                        let tipY = height + arrowSize * 1.6

                        path.move(to: CGPoint(x: x, y: startY))
                        path.addLine(to: CGPoint(x: x, y: tipY - arrowSize))

                    case .cornerDownRight:
                        let startX = width
                        let startY = height * 0.5

                        let elbowX = startX + arrowSize * 1
                        let elbowY = startY

                        let tipX = elbowX
                        let tipY = elbowY + arrowSize * 1.6

                        path.move(to: CGPoint(x: startX, y: elbowY))
                        path.addLine(to: CGPoint(x: elbowX, y: elbowY))
                        path.addLine(to: CGPoint(x: elbowX, y: tipY - arrowSize))

                    case .cornerRightDown:
                        let startX = width * 0.5
                        let startY = height

                        let elbowX = startX
                        let elbowY = startY + arrowSize * 1

                        let tipX = elbowX + arrowSize * 1.6
                        let tipY = elbowY

                        path.move(to: CGPoint(x: startX, y: startY))
                        path.addLine(to: CGPoint(x: elbowX, y: elbowY))
                        path.addLine(to: CGPoint(x: tipX - arrowSize, y: tipY))
                    }
                }
                .stroke(
                    Color.black,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                // ===== Pointes pleines =====

                Path { path in
                    switch style {

                    case .right:
                        let y = height * 0.5
                        let tipX = width + arrowSize * 1.6

                        path.move(to: CGPoint(x: tipX, y: y))
                        path.addLine(to: CGPoint(x: tipX - arrowSize, y: y - arrowSize * 0.45))
                        path.addLine(to: CGPoint(x: tipX - arrowSize, y: y + arrowSize * 0.45))
                        path.closeSubpath()
                    case .down:
                        let x = width * 0.5
                        let tipY = height + arrowSize * 1.6

                        path.move(to: CGPoint(x: x, y: tipY))
                        path.addLine(to: CGPoint(x: x - arrowSize * 0.45, y: tipY - arrowSize))
                        path.addLine(to: CGPoint(x: x + arrowSize * 0.45, y: tipY - arrowSize))
                        path.closeSubpath()

                    case .cornerDownRight:
                        let elbowX = width + arrowSize * 1

                        let elbowY = height * 0.5

                        let tipY = elbowY + arrowSize * 1.6

                        path.move(to: CGPoint(x: elbowX, y: tipY))
                        path.addLine(to: CGPoint(x: elbowX - arrowSize * 0.45, y: tipY - arrowSize))
                        path.addLine(to: CGPoint(x: elbowX + arrowSize * 0.45, y: tipY - arrowSize))
                        path.closeSubpath()

                    case .cornerRightDown:
                        let startX = width * 0.5
                        let startY = height

                        let elbowX = startX
                        let elbowY = startY + arrowSize * 1

                        let tipX = elbowX + arrowSize * 1.6
                        let tipY = elbowY

                        path.move(to: CGPoint(x: tipX, y: tipY))
                        path.addLine(to: CGPoint(
                            x: tipX - arrowSize,
                            y: tipY - arrowSize * 0.45
                        ))
                        path.addLine(to: CGPoint(
                            x: tipX - arrowSize,
                            y: tipY + arrowSize * 0.45
                        ))
                        path.closeSubpath()
                    }
                }
                .fill(Color.black)
            }
        }
        .allowsHitTesting(false)
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
                ProfileSecureField(text: $currentPassword, prompt: "Mot de passe", textContentType: nil)
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
                ProfileSecureField(text: $currentPassword, prompt: "Ancien mot de passe", textContentType: nil)
                ProfileSecureField(text: $newPassword, prompt: "Nouveau mot de passe", textContentType: nil)
                ProfileSecureField(text: $confirmPassword, prompt: "Confirmation", textContentType: nil)
                savePanelButton(title: "Changer le mot de passe")
            }
        case .deleteAccount:
            VStack(alignment: .leading, spacing: 12) {
                SettingsTextPanel(lines: [
                    "Cette action supprime définitivement le compte.",
                    isAppleAccount ? "Une confirmation Apple sera demandee pour supprimer le compte." : "Entre ton mot de passe actuel pour confirmer."
                ])
                if !isAppleAccount {
                    ProfileSecureField(text: $currentPassword, prompt: "Ancien mot de passe", textContentType: nil)
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
