const LoginView = (() => {
  const form = document.getElementById("login-form");
  const emailInput = document.getElementById("email");
  const passwordInput = document.getElementById("password");
  const button = document.getElementById("login-button");
  const message = document.getElementById("login-message");
  const passwordToggle = document.getElementById("password-toggle");

  function setMessage(text, tone = "neutral") {
    message.textContent = text;
    message.dataset.tone = tone;
  }

  function setLoading(isLoading) {
    button.disabled = isLoading;
    button.textContent = isLoading ? "Connexion..." : "Se connecter";
  }

  function normalizeEmail(value) {
    return String(value || "").trim().toLowerCase();
  }

  function hasValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  function mapAuthError(error) {
    const code = error && error.code;

    if (code === "auth/invalid-credential" || code === "auth/wrong-password") {
      return "Adresse e-mail ou mot de passe incorrect.";
    }

    if (code === "auth/user-not-found") {
      return "Aucun compte ne correspond a cette adresse.";
    }

    if (code === "auth/too-many-requests") {
      return "Trop de tentatives. Reessaie dans quelques minutes.";
    }

    return error.message || "Connexion impossible pour le moment.";
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
      setMessage("Verification du statut Editor...");

      try {
        await AuthGate.signIn(normalizedEmail, passwordInput.value);
        setMessage("");
      } catch (error) {
        setMessage(mapAuthError(error), "error");
      } finally {
        setLoading(false);
      }
    });

    if (passwordToggle) {
      passwordToggle.addEventListener("click", () => {
        const shouldShowPassword = passwordInput.type === "password";
        passwordInput.type = shouldShowPassword ? "text" : "password";
        passwordToggle.textContent = shouldShowPassword ? "Masquer" : "Afficher";
        passwordToggle.setAttribute("aria-pressed", String(shouldShowPassword));
        passwordInput.focus();
      });
    }
  }

  return { init, setMessage };
})();
