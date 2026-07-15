import FirebaseAuth
import SwiftUI

struct ContentView: View {
    @State private var isLaunchComplete = false
    @State private var currentUser: User?
    @State private var authStateHandle: AuthStateDidChangeListenerHandle?
    @State private var hasRequestedTrackingPermission = false

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
        .task(id: trackingPermissionRequestID) {
            requestTrackingPermissionIfAuthenticated()
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
                },
                onSignedOut: {
                    currentUser = nil
                }
            )
        } else {
            AccountSetupView { user in
                currentUser = user
            }
        }
    }

    private var trackingPermissionRequestID: String {
        "\(isLaunchComplete)-\(currentUser?.uid ?? "anonymous")"
    }

    private func startAuthStateListener() {
        guard authStateHandle == nil else {
            return
        }

        currentUser = Auth.auth().currentUser
        authStateHandle = Auth.auth().addStateDidChangeListener { _, user in
            currentUser = user
        }
    }

    private func stopAuthStateListener() {
        guard let authStateHandle else {
            return
        }

        Auth.auth().removeStateDidChangeListener(authStateHandle)
        self.authStateHandle = nil
    }

    private func requestTrackingPermissionIfAuthenticated() {
        guard isLaunchComplete, currentUser != nil, !hasRequestedTrackingPermission else {
            return
        }

        hasRequestedTrackingPermission = true
        TrackingPermissionRequester.requestAfterAuthenticationIfPossible()
    }
}

#Preview {
    ContentView()
}
