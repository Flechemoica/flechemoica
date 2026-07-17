const MfaView = (() => {
  let form;
  let title;
  let description;
  let phoneGroup;
  let phoneInput;
  let sendButton;
  let codeGroup;
  let codeInput;
  let confirmButton;
  let cancelButton;
  let message;
  let verifier = null;
  let mode = null;
  let pendingUser = null;
  let pendingProfile = null;
  let pendingResolver = null;
  let verificationId = null;

  function init() {
    form = document.getElementById("mfa-form");
    title = document.getElementById("mfa-title");
    description = document.getElementById("mfa-description");
    phoneGroup = document.getElementById("mfa-phone-group");
    phoneInput = document.getElementById("mfa-phone");
    sendButton = document.getElementById("mfa-send-button");
    codeGroup = document.getElementById("mfa-code-group");
    codeInput = document.getElementById("mfa-code");
    confirmButton = document.getElementById("mfa-confirm-button");
    cancelButton = document.getElementById("mfa-cancel-button");
    message = document.getElementById("mfa-message");

    sendButton.addEventListener("click", sendCode);
    form.addEventListener("submit", confirmCode);
    cancelButton.addEventListener("click", cancel);
  }

  function show() {
    LoginView.hide();
    form.classList.remove("is-hidden");
  }

  function hide() {
    form.classList.add("is-hidden");
    reset();
  }

  function reset() {
    setMessage("");
    setLoading(false);
    clearVerifier();
    verificationId = null;
    codeInput.value = "";
    codeGroup.classList.add("is-hidden");
    confirmButton.classList.add("is-hidden");
    sendButton.classList.remove("is-hidden");
  }

  function startEnrollment(user, profile) {
    mode = "enroll";
    pendingUser = user;
    pendingProfile = profile;
    pendingResolver = null;
    title.textContent = "Activer la double authentification";
    description.textContent = "Un numéro de téléphone est requis pour protéger l'accès Administration.";
    phoneGroup.classList.remove("is-hidden");
    phoneInput.required = true;
    phoneInput.value = "";
    show();
  }

  function startSignIn(resolver) {
    mode = "signin";
    pendingResolver = resolver;
    pendingUser = null;
    pendingProfile = null;
    title.textContent = "Validation SMS";
    description.textContent = "Un code SMS est nécessaire pour finaliser la connexion.";
    phoneGroup.classList.add("is-hidden");
    phoneInput.required = false;
    show();
  }

  function setMessage(text, tone = "neutral") {
    message.textContent = text;
    message.dataset.tone = tone;
  }

  function setLoading(isLoading) {
    sendButton.disabled = isLoading;
    confirmButton.disabled = isLoading;
    cancelButton.disabled = isLoading;
  }

  function getVerifier() {
    if (!verifier) {
      verifier = new firebase.auth.RecaptchaVerifier("mfa-send-button", {
        size: "invisible",
        "expired-callback": clearVerifier,
      });
    }

    return verifier;
  }

  function clearVerifier() {
    if (!verifier) return;

    verifier.clear();
    verifier = null;
  }

  async function sendCode() {
    try {
      setMessage("Envoi du code SMS...");

      const provider = new firebase.auth.PhoneAuthProvider();
      const verifierInstance = getVerifier();
      setLoading(true);

      if (mode === "enroll") {
        const phoneNumber = phoneInput.value.trim();
        if (!phoneNumber.startsWith("+")) {
          setMessage("Indiquez le numéro au format international, par exemple +33612345678.", "error");
          return;
        }

        const session = await pendingUser.multiFactor.getSession();
        verificationId = await provider.verifyPhoneNumber({ phoneNumber, session }, verifierInstance);
      } else {
        const hint = pendingResolver.hints[0];
        verificationId = await provider.verifyPhoneNumber(
          { multiFactorHint: hint, session: pendingResolver.session },
          verifierInstance
        );
      }

      sendButton.classList.add("is-hidden");
      codeGroup.classList.remove("is-hidden");
      confirmButton.classList.remove("is-hidden");
      codeInput.focus();
      setMessage("Code SMS envoyé.");
    } catch (error) {
      clearVerifier();
      setMessage(mapMfaError(error), "error");
    } finally {
      setLoading(false);
    }
  }

  async function confirmCode(event) {
    event.preventDefault();

    const code = codeInput.value.trim();
    if (!verificationId || !code) {
      setMessage("Indiquez le code SMS reçu.", "error");
      return;
    }

    try {
      setLoading(true);
      setMessage("Validation du code...");

      const credential = firebase.auth.PhoneAuthProvider.credential(verificationId, code);
      const assertion = firebase.auth.PhoneMultiFactorGenerator.assertion(credential);

      if (mode === "enroll") {
        await pendingUser.multiFactor.enroll(assertion, "Téléphone");
        await markMfaEnabled(pendingUser, pendingProfile);
        hide();
        DashboardView.showDashboard(pendingUser);
        return;
      }

      const credentials = await AuthGate.completeMfaSignIn(pendingResolver, assertion);
      hide();
      DashboardView.showDashboard(credentials.user);
    } catch (error) {
      setMessage(error.message || "Code SMS invalide.", "error");
    } finally {
      setLoading(false);
    }
  }

  async function markMfaEnabled(user, profile) {
    const { firestore } = AuthGate.ensureFirebase();
    if (!firestore || profile?.source !== "firestore") return;

    await firestore.collection("users").doc(profile.id).update({
      mfaStatus: "enabled",
      mfaEnabledAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    });
  }

  async function cancel() {
    hide();
    LoginView.show();
    await AuthGate.signOut();
  }

  function mapMfaError(error) {
    const code = error && error.code;

    if (code === "auth/invalid-app-credential") {
      return "La vérification reCAPTCHA a expiré ou le domaine n'est pas autorisé. Rechargez la page, puis réessayez.";
    }

    if (code === "auth/operation-not-allowed") {
      return "L'envoi SMS est bloqué par la configuration Firebase pour cette région.";
    }

    if (code === "auth/too-many-requests") {
      return "Trop de demandes SMS. Réessayez plus tard.";
    }

    return error.message || "Impossible d'envoyer le code SMS.";
  }

  return {
    init,
    hide,
    startEnrollment,
    startSignIn,
  };
})();
