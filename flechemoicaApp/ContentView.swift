import FirebaseAuth
import SwiftUI

struct ContentView: View {
    @State private var isLaunchComplete = false
    @State private var currentUser: User?
    @State private var authStateHandle: AuthStateDidChangeListenerHandle?

    var body: some View {
        ZStack {
            mainContent
                .opacity(isLaunchComplete ? 1 : 0)
                .allowsHitTesting(isLaunchComplete)

            if !isLaunchComplete {
                LaunchScreenView(isComplete: $isLaunchComplete)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isLaunchComplete)
        .animation(.easeInOut(duration: 0.25), value: currentUser?.uid)
        .task(id: advertisingConsentRequestID) {
            prepareAdvertisingIfAuthenticated()
        }
        .onAppear {
            startAuthStateListener()
        }
        .onDisappear {
            stopAuthStateListener()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let authenticatedUser = currentUser {
            HomeView(
                user: authenticatedUser,
                onUserChanged: { user in
                    currentUser = user
                    configurePushNotifications(for: user)
                },
                onSignedOut: {
                    currentUser = nil
                }
            )
        } else {
            AccountSetupView { user in
                currentUser = user
                configurePushNotifications(for: user)
            }
        }
    }

    private var advertisingConsentRequestID: String {
        "\(isLaunchComplete)-\(currentUser?.uid ?? "anonymous")"
    }

    private func startAuthStateListener() {
        guard authStateHandle == nil else {
            return
        }

        currentUser = Auth.auth().currentUser
        if let currentUser {
            configurePushNotifications(for: currentUser)
        }

        authStateHandle = Auth.auth().addStateDidChangeListener { _, user in
            if user == nil {
                currentUser = nil
            } else if let user {
                currentUser = user
                configurePushNotifications(for: user)
            }
        }
    }

    private func stopAuthStateListener() {
        guard let authStateHandle else {
            return
        }

        Auth.auth().removeStateDidChangeListener(authStateHandle)
        self.authStateHandle = nil
    }

    private func prepareAdvertisingIfAuthenticated() {
        guard isLaunchComplete, currentUser != nil else {
            return
        }

        AdvertisingConsentManager.shared.prepareAfterAuthentication()
    }

    private func configurePushNotifications(for user: User) {
        PushNotificationManager.shared.configureForAuthenticatedUser(userID: user.uid)
    }
}

#Preview {
    ContentView()
}
