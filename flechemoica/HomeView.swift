import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import UIKit

struct HomeView: View {
    fileprivate static let featuredProfileUID = "KiXhyFMwBjenEW91pEpQXKjZAi52"

    let user: User
    var onUserChanged: (User) -> Void = { _ in }
    var onSignedOut: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var isEditor = false
    @State private var isShowingPublicProfile = false
    @State private var isShowingFeaturedProfile = false
    @State private var isShowingSettings = false
    @State private var featuredProfile = FeaturedProfile.placeholder
    @State private var displayNameOverride: String?
    @State private var emailOverride: String?
    @State private var photoURLOverride: URL?

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

        if isShowingFeaturedProfile {
            return "\(featuredProfile.displayName).exe"
        }

        return isShowingPublicProfile ? "\(displayName).exe" : "Accueil.exe"
    }

    private var avatarName: String {
        let photoURL = photoURLOverride ?? user.photoURL

        if let host = photoURL?.host, !host.isEmpty {
            return host.replacingOccurrences(of: ".png", with: "")
        }

        return "08"
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
                            signedOut: handleSignedOut
                        )
                    } else if isShowingPublicProfile {
                        PublicProfileContent(
                            displayName: displayName,
                            avatarName: avatarName,
                            isEditor: isEditor,
                            backAction: { isShowingPublicProfile = false },
                            settingsAction: { isShowingSettings = true }
                        )
                    } else if isShowingFeaturedProfile {
                        PublicProfileContent(
                            displayName: featuredProfile.displayName,
                            avatarName: featuredProfile.avatarName,
                            isEditor: featuredProfile.isEditor,
                            backAction: { isShowingFeaturedProfile = false }
                        )
                    } else {
                        HomeContent(
                            displayName: displayName,
                            avatarName: avatarName,
                            isEditor: isEditor,
                            featuredProfile: featuredProfile,
                            profileAction: { isShowingPublicProfile = true },
                            featuredProfileAction: { isShowingFeaturedProfile = true }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            }
        }
        .task(id: user.uid) {
            await refreshAuthenticatedProfile()
            await loadFeaturedProfile()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshAuthenticatedProfile()
        }
    }

    private func refreshAuthenticatedProfile() async {
        try? await user.reload()

        let refreshedUser = Auth.auth().currentUser ?? user
        displayNameOverride = refreshedUser.displayName
        emailOverride = refreshedUser.email
        photoURLOverride = refreshedUser.photoURL
        onUserChanged(refreshedUser)
        await loadProfileMetadataAndSyncEmail(for: refreshedUser)
    }

    private func loadProfileMetadataAndSyncEmail(for refreshedUser: User) async {
        do {
            let document = Firestore.firestore()
                .collection("users")
                .document(refreshedUser.uid)
            let snapshot = try await document.getDocument()
            let data = snapshot.data()
            let role = data?["role"] as? String
            isEditor = role == "editor"

            await syncAuthenticatedEmailIfNeeded(
                refreshedUser: refreshedUser,
                document: document,
                storedEmail: data?["email"] as? String
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

    private func loadFeaturedProfile() async {
        do {
            let database = Firestore.firestore()
            let publicSnapshot = try await database
                .collection("publicProfiles")
                .document(Self.featuredProfileUID)
                .getDocument()
            let publicData = publicSnapshot.data()
            let userSnapshot = try? await database
                .collection("users")
                .document(Self.featuredProfileUID)
                .getDocument()
            let userData = userSnapshot?.data()

            featuredProfile = FeaturedProfile(
                uid: Self.featuredProfileUID,
                displayName: (publicData?["pseudo"] as? String) ?? "Profil",
                avatarName: ((publicData?["avatarID"] as? String) ?? "08.png").replacingOccurrences(of: ".png", with: ""),
                isEditor: (userData?["role"] as? String) == "editor"
            )
        } catch {
            featuredProfile = .placeholder
        }
    }

    private func handleUserChanged(_ changedUser: User) {
        displayNameOverride = changedUser.displayName
        emailOverride = changedUser.email
        photoURLOverride = changedUser.photoURL
        onUserChanged(changedUser)
    }

    private func handleSignedOut() {
        onSignedOut()
    }
}

private struct FeaturedProfile {
    let uid: String
    let displayName: String
    let avatarName: String
    let isEditor: Bool

    static let placeholder = FeaturedProfile(
        uid: HomeView.featuredProfileUID,
        displayName: "Profil",
        avatarName: "08",
        isEditor: false
    )
}

private struct HomeContent: View {
    let displayName: String
    let avatarName: String
    let isEditor: Bool
    let featuredProfile: FeaturedProfile
    let profileAction: () -> Void
    let featuredProfileAction: () -> Void

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

            HomeNativeAdCard(adUnitID: "ca-app-pub-1003964550278910/3236151939")

            Button(action: featuredProfileAction) {
                ProfileSummaryCard(
                    displayName: featuredProfile.displayName,
                    avatarName: featuredProfile.avatarName,
                    isEditor: featuredProfile.isEditor,
                    eyebrow: "Profil"
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(14)
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
                        .font(.custom("Tahoma", size: 22).weight(.bold))
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
    let backAction: () -> Void
    var settingsAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    AvatarBadge(name: avatarName, size: 112)

                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text(displayName)
                                .font(.custom("Tahoma", size: 24).weight(.bold))
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

                if let settingsAction {
                    Button(action: settingsAction) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black.opacity(0.78))
                            .frame(width: 34, height: 34)
                            .background(Color.xpChrome)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reglages du profil")
                    .padding(8)
                }
            }
            .background(Color.xpPanel)
            .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))

            Button("Retour", action: backAction)
                .buttonStyle(XPButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(14)
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
    let signedOut: () -> Void

    @State private var displayName: String
    @State private var selectedAvatarIndex: Int
    @State private var savedDisplayName: String
    @State private var savedEmail: String
    @State private var savedAvatarName: String
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var statusText = ""
    @State private var isSubmitting = false
    @State private var isShowingDeleteConfirmation = false

    init(
        user: User,
        initialDisplayName: String,
        initialEmail: String,
        initialAvatarName: String,
        backAction: @escaping () -> Void,
        userChanged: @escaping (User) -> Void,
        signedOut: @escaping () -> Void
    ) {
        self.user = user
        self.initialDisplayName = initialDisplayName
        self.initialEmail = initialEmail
        self.initialAvatarName = initialAvatarName
        self.backAction = backAction
        self.userChanged = userChanged
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

    private var canSave: Bool {
        guard !isSubmitting else { return false }
        guard !trimmedDisplayName.isEmpty else { return false }
        guard hasAccountChanges || hasAvatarChanges || wantsPasswordChange else { return false }

        if wantsPasswordChange {
            return currentPassword.count >= 6 && newPassword.count >= 6 && newPassword == confirmPassword
        }

        return true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionTitle("Profil")
                    ProfileAvatarPickerRow(
                        avatarName: selectedAvatarName,
                        previousAction: selectPreviousAvatar,
                        nextAction: selectNextAvatar
                    )
                    ProfileTextField(text: $displayName, prompt: "Nom d'utilisateur")
                    ProfileReadOnlyField(text: savedEmail, prompt: "Adresse e-mail")
                }
                .settingsPanel()

                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionTitle("Mot de passe")
                    ProfileSecureField(text: $currentPassword, prompt: "Ancien mot de passe")
                    ProfileSecureField(text: $newPassword, prompt: "Nouveau mot de passe", textContentType: .newPassword)
                    ProfileSecureField(text: $confirmPassword, prompt: "Confirmation", textContentType: .newPassword)
                }
                .settingsPanel()

                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionTitle("Suppression du compte")
                    HStack {
                        Spacer(minLength: 0)
                        Button("Supprimer le compte") {
                            requestAccountDeletionConfirmation()
                        }
                        .buttonStyle(XPButtonStyle(foregroundColor: .red))
                        .disabled(isSubmitting)
                        Spacer(minLength: 0)
                    }
                }
                .settingsPanel()

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Retour", action: backAction)
                            .buttonStyle(XPButtonStyle())
                            .disabled(isSubmitting)

                        Button(isSubmitting ? "Enregistrement..." : "Enregistrer") {
                            saveTapped()
                        }
                        .buttonStyle(XPButtonStyle())
                        .opacity(canSave ? 1 : 0.55)
                        .disabled(!canSave)
                    }

                    Button("Deconnexion") {
                        signOutTapped()
                    }
                    .buttonStyle(XPButtonStyle(foregroundColor: .red))
                    .disabled(isSubmitting)

                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.custom("Tahoma", size: 13))
                            .foregroundStyle(.black.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.top, 2)

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .confirmationDialog(
            "Supprimer definitivement ce compte ?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer le compte", role: .destructive) {
                deleteAccountTapped()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le compte Firebase Auth et les documents Firestore users/publicProfiles seront supprimes.")
        }
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

    private func requestAccountDeletionConfirmation() {
        guard currentPassword.count >= 6 else {
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
        guard currentPassword.count >= 6 else {
            statusText = "Entre ton ancien mot de passe pour supprimer le compte."
            return
        }

        isSubmitting = true
        statusText = "Suppression du compte..."

        Task {
            do {
                try await reauthenticateUser()
                try await deleteUserDocuments()
                try await user.delete()

                await MainActor.run {
                    signedOut()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    statusText = firebaseMessage(for: error)
                }
            }
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

    private func validateProfileAvailability() async throws {
        let database = Firestore.firestore()

        if displayNameKey != savedDisplayNameKey {
            let profileKeySnapshot = try await database
                .collection("publicProfiles")
                .whereField("pseudoKey", isEqualTo: displayNameKey)
                .limit(to: 1)
                .getDocuments()
            let profileSnapshot = try await database
                .collection("publicProfiles")
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

        try await database
            .collection("publicProfiles")
            .document(user.uid)
            .setData([
                "uid": user.uid,
                "pseudo": trimmedDisplayName,
                "pseudoKey": displayNameKey,
                "avatarID": selectedAvatarID,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    private func deleteUserDocuments() async throws {
        let database = Firestore.firestore()
        try await database.collection("users").document(user.uid).delete()
        try await database.collection("publicProfiles").document(user.uid).delete()
    }

    private func firebaseMessage(for error: Error) -> String {
        if let profileError = error as? ProfileSettingsError {
            return profileError.message
        }

        let nsError = error as NSError
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
}

private enum ProfileSettingsError: Error {
    case displayNameAlreadyTaken

    var message: String {
        switch self {
        case .displayNameAlreadyTaken:
            return "Ce nom d'utilisateur est deja pris."
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
            .font(.custom("Tahoma", size: 14).weight(.bold))
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
        SecureField(text: $text) {
            Text(prompt)
                .foregroundStyle(.gray)
        }
        .textContentType(textContentType)
        .profileInputStyle()
    }
}

private struct EditorBadge: View {
    var body: some View {
        Text("Éditeur")
            .font(.custom("Tahoma", size: 12).weight(.bold))
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
                    .font(.custom("Tahoma", size: 18).weight(.bold))
                    .foregroundStyle(.black.opacity(0.65))
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 1))
    }
}

private extension View {
    func settingsPanel() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.xpPanel)
            .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
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
