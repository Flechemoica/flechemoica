const DashboardView = (() => {
  const loginView = document.getElementById("login-view");
  const dashboardView = document.getElementById("dashboard-view");
  const accountEmail = document.getElementById("account-email");
  const logoutButton = document.getElementById("logout-button");

  function showLogin() {
    loginView.classList.remove("is-hidden");
    dashboardView.classList.add("is-hidden");
    accountEmail.textContent = "";
  }

  function showDashboard(user) {
    accountEmail.textContent = user.email || "";
    loginView.classList.add("is-hidden");
    dashboardView.classList.remove("is-hidden");
  }

  function init() {
    logoutButton.addEventListener("click", () => {
      AuthGate.signOut();
    });
  }

  return {
    init,
    showDashboard,
    showLogin,
  };
})();
