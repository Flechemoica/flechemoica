import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import UIKit

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
                                        Text("FLÈCHE")
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
                                        XPTextField(text: $pseudo, prompt: "Pseudo")
                                    }

                                    XPTextField(text: $email, prompt: "E-mail", keyboard: .emailAddress, textContentType: .emailAddress)
                                    XPSecureField(text: $password, prompt: "Mot de Passe", textContentType: authMode == .signUp ? .newPassword : .password)

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
        saveUserProfileInBackground(for: result.user)

        await MainActor.run {
            isSubmitting = false
            onAuthenticated(result.user)
        }
    }

    private func saveUserProfileInBackground(for user: User) {
        Task {
            try? await saveUserProfile(for: user)
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
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)

        try await database
            .collection("publicProfiles")
            .document(user.uid)
            .setData([
                "uid": user.uid,
                "pseudo": trimmedPseudo,
                "pseudoKey": pseudoKey,
                "avatarID": selectedAvatarID,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    private func signIn() async throws {
        let result = try await Auth.auth().signIn(withEmail: cleanEmail, password: password)

        await MainActor.run {
            isSubmitting = false
            onAuthenticated(result.user)
        }
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firebaseMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return nsError.localizedDescription
        }

        switch code {
        case .emailAlreadyInUse:
            return "Cet e-mail a déjà un compte."
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
}

private struct AccountLegalFooter: View {
    private let legalNoticeURL = URL(string: "https://flechemoica.fr/mentions-legales.html")
    private let privacyURL = URL(string: "https://flechemoica.fr/politique-confidentialite.html")

    var body: some View {
        HStack(spacing: 10) {
            Text("© 2026 Flèche-moi ça")
                .layoutPriority(1)

            Spacer(minLength: 4)

            if let legalNoticeURL {
                Link("Mentions légales", destination: legalNoticeURL)
            }

            if let privacyURL {
                Link("Politique de confidentialité", destination: privacyURL)
            }
        }
        .font(.xpTahoma(size: 13))
        .foregroundStyle(Color.black.opacity(0.62))
        .multilineTextAlignment(.leading)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.xpChrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(red: 0.79, green: 0.77, blue: 0.69)).frame(height: 1)
        }
    }
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
        .font(.custom("Tahoma", size: 13))
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .frame(height: 34)
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
        SecureField(text: $text) {
            Text(prompt)
                .foregroundStyle(.gray)
        }
        .textContentType(textContentType)
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
