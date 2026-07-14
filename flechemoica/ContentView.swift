import FirebaseAuth
import SwiftUI

struct ContentView: View {
    @State private var isLaunchComplete = false
    @State private var currentUser: User?
    @State private var hasRequestedTrackingPermission = false

    var body: some View {
        ZStack {
            if isLaunchComplete {
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
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                } else {
                    AccountSetupView { user in
                        currentUser = user
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            } else {
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
            currentUser = Auth.auth().currentUser
        }
    }

    private var trackingPermissionRequestID: String {
        "\(isLaunchComplete)-\(currentUser?.uid ?? "anonymous")"
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
