const DashboardView = (() => {
  const loginView = document.getElementById("login-view");
  const dashboardView = document.getElementById("dashboard-view");
  const accountEmail = document.getElementById("account-email");
  const logoutButton = document.getElementById("logout-button");
  const homeButton = document.getElementById("dashboard-home-button");
  const navItems = Array.from(document.querySelectorAll("[data-panel-target]"));
  const workspacePanels = Array.from(document.querySelectorAll(".workspace-panel"));

  function showPanel(panelID) {
    navItems.forEach((item) => {
      item.classList.toggle("is-active", item.dataset.panelTarget === panelID);
    });

    workspacePanels.forEach((panel) => {
      panel.classList.toggle("is-hidden", panel.id !== panelID);
    });

    if (panelID === "users-panel") {
      UsersView.start();
    } else {
      UsersView.stop();
    }
  }

  function showLogin() {
    loginView.classList.remove("is-hidden");
    dashboardView.classList.add("is-hidden");
    accountEmail.textContent = "";
    UsersView.stop();
  }

  function showDashboard(user) {
    accountEmail.textContent = user.email || "";
    loginView.classList.add("is-hidden");
    dashboardView.classList.remove("is-hidden");
    showPanel("overview-panel");
  }

  function init() {
    UsersView.init();

    navItems.forEach((item) => {
      item.addEventListener("click", () => {
        showPanel(item.dataset.panelTarget);
      });
    });

    logoutButton.addEventListener("click", () => {
      AuthGate.signOut();
    });

    homeButton.addEventListener("click", () => {
      showPanel("overview-panel");
    });
  }

  return {
    init,
    showDashboard,
    showLogin,
  };
})();
