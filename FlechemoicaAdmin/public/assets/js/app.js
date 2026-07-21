window.addEventListener("DOMContentLoaded", () => {
  registerAdminCacheWorker();

  LoginView.init();
  DashboardView.init();

  AuthGate.onEditorStateChanged(({ user, profile, error }) => {
    if (user) {
      LoginView.show();
      DashboardView.showDashboard(user, profile);
      return;
    }

    DashboardView.showLogin();

    if (error) return;
  });
});

function registerAdminCacheWorker() {
  if (!("serviceWorker" in navigator)) {
    return;
  }

  navigator.serviceWorker
    .register("/admin-cache-sw.js", { scope: "/" })
    .catch((error) => {
      console.warn("Cache admin indisponible:", error);
    });
}
