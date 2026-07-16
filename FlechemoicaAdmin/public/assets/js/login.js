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
      setLoading(true);
      setMessage("Verification du compte...");

      try {
        await AuthGate.signIn(emailInput.value, passwordInput.value);
        setMessage("");
      } catch (error) {
        setMessage(mapAuthError(error), "error");
      } finally {
        setLoading(false);
      }
    });
  }

  return { init, setMessage };
})();
