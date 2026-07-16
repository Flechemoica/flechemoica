window.addEventListener("DOMContentLoaded", () => {
  LoginView.init();
  DashboardView.init();

  AuthGate.onEditorStateChanged(({ user, error }) => {
    if (user) {
      DashboardView.showDashboard(user);
      return;
    }

    DashboardView.showLogin();

    if (error) {
      LoginView.setMessage("");
    }
  });
});
