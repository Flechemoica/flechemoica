const LoginView = (() => {
  const form = document.getElementById("login-form");
  const emailInput = document.getElementById("email");
  const passwordInput = document.getElementById("password");
  const button = document.getElementById("login-button");
  const message = document.getElementById("login-message");

  function setMessage(text, tone = "neutral") {
    message.textContent = text;
    message.dataset.tone = tone;
  }

  function setLoading(isLoading) {
    button.disabled = isLoading;
    button.textContent = isLoading ? "Connexion..." : "Se connecter";
  }

  function show() {
    form.classList.remove("is-hidden");
  }

  function hide() {
    form.classList.add("is-hidden");
  }

  function normalizeEmail(value) {
    return String(value || "").trim().toLowerCase();
  }

  function hasValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  function mapAuthError(error) {
    const code = error && error.code;
    const message = error && error.message;

    if (code === "auth/invalid-credential" || code === "auth/wrong-password") {
      return "Adresse e-mail ou mot de passe incorrect.";
    }

    if (code === "auth/user-not-found") {
      return "Aucun compte ne correspond a cette adresse.";
    }

    if (code === "auth/too-many-requests") {
      return "Trop de tentatives. Reessaie dans quelques minutes.";
    }

    if (code === "permission-denied" || message === "Missing or insufficient permissions.") {
      return "Accès non autorisé.";
    }

    return message || "Connexion impossible pour le moment.";
  }

  function init() {
    if (!form) return;

    form.addEventListener("submit", async (event) => {
      event.preventDefault();

      const normalizedEmail = normalizeEmail(emailInput.value);
      emailInput.value = normalizedEmail;

      if (!hasValidEmail(normalizedEmail)) {
        setMessage("Adresse e-mail invalide.", "error");
        emailInput.focus();
        return;
      }

      if (!passwordInput.value) {
        setMessage("Mot de passe requis.", "error");
        passwordInput.focus();
        return;
      }

      setLoading(true);
      setMessage("Vérification de l'accès Administration...");

      try {
        await AuthGate.signIn(normalizedEmail, passwordInput.value);
        setMessage("");
      } catch (error) {
        setMessage(mapAuthError(error), "error");
      } finally {
        setLoading(false);
      }
    });

  }

  return { init, setMessage, show, hide };
})();
