window.addEventListener("DOMContentLoaded", () => {
  LoginView.init();
  DashboardView.init();

  AuthGate.onEditorStateChanged(({ user, error }) => {
    if (user) {
      LoginView.show();
      DashboardView.showDashboard(user);
      return;
    }

    DashboardView.showLogin();

    if (error) return;
  });
});
