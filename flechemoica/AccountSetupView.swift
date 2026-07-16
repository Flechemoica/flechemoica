import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import SwiftUI
import UIKit
import WebKit

struct AccountSetupView: View {
    enum AuthMode {
        case signUp
        case signIn

        var primaryButtonTitle: String {
            switch self {
            case .signUp: "Créer le compte"
            case .signIn: "Se connecter"
            }
        }

        var windowTitle: String {
            switch self {
            case .signUp: "Inscription.exe"
            case .signIn: "Connexion.exe"
            }
        }
    }

    private static let avatarNames = ["01", "02", "03", "04", "05", "06", "07", "08", "09"]

    var onAuthenticated: (User) -> Void = { _ in }

    @State private var authMode: AuthMode = .signUp
    @State private var pseudo = ""
    @State private var email = ""
    @State private var password = ""
    @State private var selectedAvatarIndex = 7
    @State private var statusText = ""
    @State private var isSubmitting = false
    @State private var isSendingPasswordReset = false
    @State private var currentAppleSignInNonce: String?
    @State private var appleSignInCoordinator: AppleSignInCoordinator?

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                XPWindow(title: authMode.windowTitle) {
                    VStack(spacing: 0) {
                        XPMenuBar(selectedMode: $authMode) { mode in
                            switchMode(to: mode)
                        }

                        ScrollView {
                            VStack(spacing: 18) {
                                HStack(spacing: 14) {
                                    XPLogoView(size: 86)

                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("FLÈCHE-")
                                        Text("MOI ÇA")
                                    }
                                    .font(.system(size: 25, weight: .bold).italic())
                                    .foregroundStyle(.black)
                                    .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 18)
                                .padding(.horizontal, 22)

                                VStack(alignment: .leading, spacing: 14) {
                                    if authMode == .signUp {
                                        XPTextField(text: $pseudo, prompt: "Pseudo", textContentType: .nickname)
                                    }

                                    XPTextField(text: $email, prompt: "E-mail", keyboard: .emailAddress, textContentType: .emailAddress)
                                    XPSecureField(
                                        text: $password,
                                        prompt: "Mot de Passe",
                                        textContentType: nil
                                    )

                                    if authMode == .signUp {
                                        AvatarPickerRow(
                                            avatarName: selectedAvatarName,
                                            previousAction: selectPreviousAvatar,
                                            nextAction: selectNextAvatar
                                        )
                                    }
                                }
                                .padding(14)
                                .background(Color.xpPanel)
                                .overlay(Rectangle().stroke(Color(red: 0.5, green: 0.62, blue: 0.73), lineWidth: 2))
                                .padding(.horizontal, 14)

                                VStack(spacing: 10) {
                                    Button {
                                        submitTapped()
                                    } label: {
                                        Text(isSubmitting ? submittingButtonTitle : authMode.primaryButtonTitle)
                                    }
                                    .buttonStyle(XPButtonStyle())
                                    .opacity(canSubmit && !isSubmitting ? 1 : 0.55)
                                    .disabled(!canSubmit || isSubmitting)

                                    HStack(spacing: 10) {
                                        Button {
                                            signInWithAppleTapped()
                                        } label: {
                                            Image(systemName: "apple.logo")
                                                .font(.system(size: 24, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .frame(width: 44, height: 44)
                                                .background(Color.black)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Continuer avec Apple")
                                        .opacity(!isSubmitting ? 1 : 0.55)
                                        .disabled(isSubmitting)

                                        Button {
                                            signInWithGoogleTapped()
                                        } label: {
                                            Image("GoogleG")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 25, height: 25)
                                                .frame(width: 44, height: 44)
                                                .background(Color.white)
                                                .overlay(Rectangle().stroke(Color.black.opacity(0.28), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Continuer avec Google")
                                        .opacity(!isSubmitting ? 1 : 0.55)
                                        .disabled(isSubmitting)
                                    }

                                    if authMode == .signIn {
                                        Button {
                                            sendPasswordResetTapped()
                                        } label: {
                                            Text(isSendingPasswordReset ? "Envoi..." : "Mot de passe oublié ?")
                                                .font(.custom("Tahoma", size: 13))
                                                .underline()
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.black.opacity(canSendPasswordReset ? 0.85 : 0.45))
                                        .disabled(!canSendPasswordReset || isSubmitting || isSendingPasswordReset)
                                    }

                                    if !statusText.isEmpty {
                                        Text(statusText)
                                            .font(.custom("Tahoma", size: 13))
                                            .foregroundStyle(.black.opacity(0.78))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .padding(.horizontal, 18)
                                    }
                                }

                                Spacer(minLength: 0)
                                    .frame(height: 8)
                            }
                        }

                        AccountLegalFooter()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            }
        }
    }

    private var submittingButtonTitle: String {
        switch authMode {
        case .signUp: "Création..."
        case .signIn: "Connexion..."
        }
    }

    private var canSendPasswordReset: Bool {
        cleanEmail.contains("@") && !isSendingPasswordReset
    }

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidCredentials = trimmedEmail.contains("@") && password.count >= 6

        switch authMode {
        case .signUp:
            return hasValidCredentials && !pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .signIn:
            return hasValidCredentials
        }
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

    private func switchMode(to mode: AuthMode) {
        authMode = mode
        isSubmitting = false
        isSendingPasswordReset = false
        statusText = ""
    }

    private func selectPreviousAvatar() {
        selectedAvatarIndex = selectedAvatarIndex == 0 ? Self.avatarNames.count - 1 : selectedAvatarIndex - 1
    }

    private func selectNextAvatar() {
        selectedAvatarIndex = (selectedAvatarIndex + 1) % Self.avatarNames.count
    }

    private func submitTapped() {
        isSubmitting = true
        statusText = authMode == .signUp ? "Création du compte..." : "Connexion..."

        Task {
            do {
                switch authMode {
                case .signUp:
                    try await createAccount()
                case .signIn:
                    try await signIn()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    statusText = firebaseMessage(for: error)
                }
            }
        }
    }

    private func sendPasswordResetTapped() {
        guard canSendPasswordReset else {
            statusText = "Entre ton e-mail pour réinitialiser le mot de passe."
            return
        }

        isSendingPasswordReset = true
        statusText = "Envoi de l'e-mail de réinitialisation..."

        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: cleanEmail)
                await MainActor.run {
                    isSendingPasswordReset = false
                    statusText = "E-mail de réinitialisation envoyé. Vérifie ta boîte mail."
                }
            } catch {
                await MainActor.run {
                    isSendingPasswordReset = false
                    statusText = firebaseMessage(for: error)
                }
            }
        }
    }

    private func createAccount() async throws {
        let result = try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        changeRequest.photoURL = selectedAvatarURL
        try await changeRequest.commitChanges()
        _ = try await result.user.getIDTokenResult(forcingRefresh: true)
        try await saveUserProfile(for: result.user)

        await MainActor.run {
            isSubmitting = false
            onAuthenticated(result.user)
        }
    }

    private func saveUserProfile(for user: User) async throws {
        let database = Firestore.firestore()
        let trimmedPseudo = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        let pseudoKey = trimmedPseudo.lowercased()
        let emailKey = cleanEmail.lowercased()

        try await database
            .collection("users")
            .document(user.uid)
            .setData([
                "uid": user.uid,
                "email": cleanEmail,
                "emailKey": emailKey,
                "pseudo": trimmedPseudo,
                "pseudoKey": pseudoKey,
                "avatarID": selectedAvatarID,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

    }

    private func signIn() async throws {
        let result = try await Auth.auth().signIn(withEmail: cleanEmail, password: password)

        await MainActor.run {
            isSubmitting = false
            onAuthenticated(result.user)
        }
    }

    private func signInWithAppleTapped() {
        let nonce = randomNonceString()
        currentAppleSignInNonce = nonce
        isSubmitting = true
        statusText = "Connexion avec Apple..."

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let coordinator = AppleSignInCoordinator(
            onSuccess: { credential in
                Task {
                    await handleAppleSignIn(credential: credential, nonce: nonce)
                }
            },
            onFailure: { error in
                Task { @MainActor in
                    isSubmitting = false
                    appleSignInCoordinator = nil

                    if let authorizationError = error as? ASAuthorizationError,
                       authorizationError.code == .canceled {
                        statusText = ""
                    } else {
                        statusText = firebaseMessage(for: error)
                    }
                }
            }
        )

        appleSignInCoordinator = coordinator

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = coordinator
        authorizationController.presentationContextProvider = coordinator
        authorizationController.performRequests()
    }

    private func signInWithGoogleTapped() {
        isSubmitting = true
        statusText = "Connexion avec Google..."

        Task {
            do {
                let result = try await signInWithGoogle()
                try await saveGoogleUserProfile(for: result.user)

                await MainActor.run {
                    isSubmitting = false
                    onAuthenticated(result.user)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    statusText = firebaseMessage(for: error)
                }
            }
        }
    }

    private func signInWithGoogle() async throws -> AuthDataResult {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AccountSetupError.missingGoogleClientID
        }

        guard let presentingViewController = presentingViewController() else {
            throw AccountSetupError.missingPresentationAnchor
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        let googleUser = signInResult.user

        guard let idToken = googleUser.idToken?.tokenString else {
            throw AccountSetupError.missingGoogleIdentityToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )

        if let currentUser = Auth.auth().currentUser {
            return try await currentUser.link(with: credential)
        }

        return try await Auth.auth().signIn(with: credential)
    }

    private func saveGoogleUserProfile(for user: User) async throws {
        let database = Firestore.firestore()
        let document = database.collection("users").document(user.uid)
        let snapshot = try await document.getDocument()
        let existingData = snapshot.data() ?? [:]
        let resolvedEmail = user.email ?? ""
        let resolvedPseudo = user.displayName ?? resolvedEmail.components(separatedBy: "@").first ?? "Utilisateur"
        let resolvedAvatarID = (existingData["avatarID"] as? String) ?? selectedAvatarID

        var data: [String: Any] = [
            "uid": user.uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if !snapshot.exists {
            data["createdAt"] = FieldValue.serverTimestamp()
        }

        if existingData["email"] == nil, !resolvedEmail.isEmpty {
            data["email"] = resolvedEmail
            data["emailKey"] = resolvedEmail.lowercased()
        }

        if existingData["pseudo"] == nil, !resolvedPseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedPseudo = resolvedPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
            data["pseudo"] = trimmedPseudo
            data["pseudoKey"] = trimmedPseudo.lowercased()
        }

        if existingData["avatarID"] == nil {
            data["avatarID"] = resolvedAvatarID
        }

        try await document.setData(data, merge: true)

        let avatarURL = URL(string: "flechemoica-avatar://\(resolvedAvatarID)")
        if user.photoURL != avatarURL {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.photoURL = avatarURL
            try await changeRequest.commitChanges()
        }
    }

    private func handleAppleSignIn(credential appleIDCredential: ASAuthorizationAppleIDCredential, nonce: String) async {
        do {
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                throw AccountSetupError.missingAppleIdentityToken
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            let result: AuthDataResult
            if let currentUser = Auth.auth().currentUser {
                result = try await currentUser.link(with: credential)
            } else {
                result = try await Auth.auth().signIn(with: credential)
            }
            let avatarID = try await saveAppleUserProfile(for: result.user, appleCredential: appleIDCredential)
            try await updateAppleAuthProfileIfNeeded(
                for: result.user,
                appleCredential: appleIDCredential,
                avatarID: avatarID
            )

            await MainActor.run {
                isSubmitting = false
                appleSignInCoordinator = nil
                onAuthenticated(result.user)
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                appleSignInCoordinator = nil
                statusText = firebaseMessage(for: error)
            }
        }
    }

    private func saveAppleUserProfile(for user: User, appleCredential: ASAuthorizationAppleIDCredential) async throws -> String {
        let database = Firestore.firestore()
        let document = database.collection("users").document(user.uid)
        let snapshot = try await document.getDocument()
        let existingData = snapshot.data() ?? [:]
        let resolvedEmail = user.email ?? appleCredential.email ?? ""
        let resolvedPseudo = appleDisplayName(from: appleCredential) ?? user.displayName ?? resolvedEmail.components(separatedBy: "@").first ?? "Utilisateur"
        let resolvedAvatarID = (existingData["avatarID"] as? String) ?? selectedAvatarID

        var data: [String: Any] = [
            "uid": user.uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if !snapshot.exists {
            data["createdAt"] = FieldValue.serverTimestamp()
        }

        if existingData["email"] == nil, !resolvedEmail.isEmpty {
            data["email"] = resolvedEmail
            data["emailKey"] = resolvedEmail.lowercased()
        }

        if existingData["pseudo"] == nil, !resolvedPseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedPseudo = resolvedPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
            data["pseudo"] = trimmedPseudo
            data["pseudoKey"] = trimmedPseudo.lowercased()
        }

        if existingData["avatarID"] == nil {
            data["avatarID"] = resolvedAvatarID
        }

        try await document.setData(data, merge: true)
        return resolvedAvatarID
    }

    private func updateAppleAuthProfileIfNeeded(
        for user: User,
        appleCredential: ASAuthorizationAppleIDCredential,
        avatarID: String
    ) async throws {
        let avatarURL = URL(string: "flechemoica-avatar://\(avatarID)")
        let displayName = appleDisplayName(from: appleCredential)
        let needsDisplayName = (user.displayName?.isEmpty ?? true) && displayName != nil
        let needsAvatar = user.photoURL != avatarURL

        guard needsDisplayName || needsAvatar else {
            return
        }

        let changeRequest = user.createProfileChangeRequest()
        if needsDisplayName {
            changeRequest.displayName = displayName
        }
        if needsAvatar {
            changeRequest.photoURL = avatarURL
        }

        try await changeRequest.commitChanges()
    }

    private func appleDisplayName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        let formatter = PersonNameComponentsFormatter()
        let displayName = formatter.string(from: credential.fullName ?? PersonNameComponents())
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return displayName.isEmpty ? nil : displayName
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firebaseMessage(for error: Error) -> String {
        if let accountSetupError = error as? AccountSetupError,
           let message = accountSetupError.errorDescription {
            return message
        }

        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return nsError.localizedDescription
        }

        switch code {
        case .emailAlreadyInUse:
            return "Cet e-mail a déjà un compte."
        case .accountExistsWithDifferentCredential:
            return "Un compte existe déjà avec cet e-mail. Connecte-toi avec sa méthode initiale, puis lie Apple ou Google depuis le compte."
        case .credentialAlreadyInUse:
            return "Cette connexion est déjà liée à un autre compte."
        case .providerAlreadyLinked:
            return "Cette méthode de connexion est déjà liée au compte."
        case .invalidEmail:
            return "E-mail invalide."
        case .wrongPassword, .invalidCredential:
            return "Identifiants incorrects. Vérifie l'e-mail et le mot de passe."
        case .userNotFound:
            return "Aucun compte avec cet e-mail."
        case .userDisabled:
            return "Ce compte a été désactivé."
        case .tooManyRequests:
            return "Trop de tentatives. Réessaie plus tard."
        case .networkError:
            return "Problème réseau. Réessaie."
        case .weakPassword:
            return "Mot de passe trop faible."
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
                fatalError("Impossible de générer le nonce Apple.")
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

    private func presentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresentedViewController()
    }
}

private enum AccountSetupError: LocalizedError {
    case missingAppleIdentityToken
    case missingGoogleClientID
    case missingGoogleIdentityToken
    case missingPresentationAnchor

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken:
            return "Impossible de récupérer l'identité Apple."
        case .missingGoogleClientID:
            return "Configuration Google introuvable."
        case .missingGoogleIdentityToken:
            return "Impossible de récupérer l'identité Google."
        case .missingPresentationAnchor:
            return "Impossible d'ouvrir la connexion Google."
        }
    }
}

private extension UIViewController {
    func topMostPresentedViewController() -> UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController()
        }

        return self
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
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
            onFailure(AccountSetupError.missingAppleIdentityToken)
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

private struct AccountLegalFooter: View {
    private let legalNoticeURL = URL(string: "https://flechemoica.fr/mentions-legales.html")
    private let privacyURL = URL(string: "https://flechemoica.fr/privacy.html")

    @State private var presentedPage: LegalPage?

    var body: some View {
        VStack(spacing: 4) {
            Text("© 2026 Flèche-moi ça")

            HStack(spacing: 14) {
                if let legalNoticeURL {
                    Button {
                        presentedPage = LegalPage(title: "Mentions légales", url: legalNoticeURL)
                    } label: {
                        Text("Mentions légales")
                            .font(.xpTahoma(size: 13))
                    }
                    .buttonStyle(.plain)
                }

                if let privacyURL {
                    Button {
                        presentedPage = LegalPage(title: "Confidentialité", url: privacyURL)
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
            InternalWebSheet(page: page)
        }
    }
}

private struct LegalPage: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct InternalWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    let page: LegalPage

    var body: some View {
        NavigationView {
            WebView(url: page.url)
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

private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct XPMenuBar: View {
    @Binding var selectedMode: AccountSetupView.AuthMode
    let onModeSelected: (AccountSetupView.AuthMode) -> Void

    var body: some View {
        HStack(spacing: 22) {
            XPMenuButton(title: "Inscription", isSelected: selectedMode == .signUp) {
                onModeSelected(.signUp)
            }
            XPMenuButton(title: "Connexion", isSelected: selectedMode == .signIn) {
                onModeSelected(.signIn)
            }
            Spacer()
        }
        .font(.xpTahoma(size: 16))
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.xpChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(red: 0.79, green: 0.77, blue: 0.69)).frame(height: 1)
        }
    }
}

private struct XPMenuButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(isSelected)
        }
        .buttonStyle(.plain)
    }
}

private struct XPTextField: View {
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
        .xpInputStyle()
    }
}

private struct XPSecureField: View {
    @Binding var text: String
    var prompt: String
    var textContentType: UITextContentType? = .password

    var body: some View {
        SecurePasswordTextField(
            text: $text,
            placeholder: prompt,
            textContentType: textContentType
        )
        .xpInputStyle()
    }
}

private struct AvatarPickerRow: View {
    let avatarName: String
    let previousAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            XPArrowButton(title: "<", action: previousAction)
            AvatarPreview(name: avatarName)
            XPArrowButton(title: ">", action: nextAction)
            Spacer(minLength: 0)
        }
    }
}

private struct XPArrowButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(XPButtonStyle())
            .frame(width: 44)
    }
}

private struct AvatarPreview: View {
    let name: String

    var body: some View {
        ZStack {
            Color.white

            if let image = UIImage(named: name) ?? bundledPNG(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Text(name)
                    .font(.xpTahoma(size: 18, weight: .bold))
                    .foregroundStyle(.black.opacity(0.65))
            }
        }
        .frame(width: 78, height: 78)
        .clipped()
        .overlay(Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 1))
    }

    private func bundledPNG(named name: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else {
            return nil
        }

        return UIImage(contentsOfFile: path)
    }
}

private extension View {
    func xpInputStyle() -> some View {
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

#Preview {
    AccountSetupView()
}
