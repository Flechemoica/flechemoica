import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI
import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

extension Notification.Name {
    static let weeklyGridNotificationSelected = Notification.Name("weeklyGridNotificationSelected")
}

final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private let weeklyGridsTopic = "weekly_grids"
    private let allUsersTopic = "all_users"
    private var currentUserID: String?
    private var configuredUserIDs = Set<String>()
    private var pendingWeeklyGridID: String?

    private override init() {
        super.init()
    }

    func configureApplicationDelegate() {
        UNUserNotificationCenter.current().delegate = self

        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        #endif
    }

    func configureForAuthenticatedUser(userID: String) {
        currentUserID = userID
        guard !configuredUserIDs.contains(userID) else {
            refreshFCMToken()
            return
        }

        configuredUserIDs.insert(userID)

        Task {
            await requestAuthorizationAndRegister()
            subscribeToNotificationTopics()
            refreshFCMToken()
        }
    }

    @MainActor
    func consumePendingWeeklyGridID() -> String? {
        let gridID = pendingWeeklyGridID
        pendingWeeklyGridID = nil
        return gridID
    }

    @MainActor
    func clearPendingWeeklyGridID(_ gridID: String) {
        if pendingWeeklyGridID == gridID {
            pendingWeeklyGridID = nil
        }
    }

    private func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )

            guard granted else { return }

            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            return
        }
    }

    private func subscribeToNotificationTopics() {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().subscribe(toTopic: weeklyGridsTopic) { _ in }
        Messaging.messaging().subscribe(toTopic: allUsersTopic) { _ in }
        #endif
    }

    private func refreshFCMToken() {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().token { [weak self] token, _ in
            guard let self, let token else { return }
            self.saveFCMToken(token)
        }
        #endif
    }

    fileprivate func saveFCMToken(_ token: String) {
        guard let userID = currentUserID ?? Auth.auth().currentUser?.uid else {
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(userID)
            .setData([
                "fcmTokens": FieldValue.arrayUnion([token]),
                "notifications": [
                    "weeklyGrids": true,
                    "allUsers": true,
                    "topics": [weeklyGridsTopic, allUsersTopic]
                ],
                "notificationsUpdatedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    @MainActor
    fileprivate func handleWeeklyGridNotificationSelection(gridID: String) {
        pendingWeeklyGridID = gridID
        NotificationCenter.default.post(
            name: .weeklyGridNotificationSelected,
            object: nil,
            userInfo: ["gridID": gridID]
        )
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let gridID = userInfo["gridID"] as? String, !gridID.isEmpty else {
            return
        }

        await MainActor.run {
            PushNotificationManager.shared.handleWeeklyGridNotificationSelection(gridID: gridID)
        }
    }
}

#if canImport(FirebaseMessaging)
extension PushNotificationManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }

        Task { @MainActor in
            PushNotificationManager.shared.saveFCMToken(fcmToken)
        }
    }
}
#endif

final class FlecheMoicaPushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushNotificationManager.shared.configureApplicationDelegate()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }
}
